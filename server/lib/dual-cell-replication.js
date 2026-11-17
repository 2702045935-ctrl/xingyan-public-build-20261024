'use strict';

const fs = require('fs');
const path = require('path');
const { ShardCluster } = require('./shard-runtime');
const { ShardEventBus } = require('./shard-event-bus');
const { ShardMutationGateway } = require('./shard-gateway');
const { ShardLeaseManager } = require('./shard-lease');
const { resolveRoute, verifyRoutePlan } = require('./shard-route-plan');
const { validateActiveDualCellPlan } = require('./dual-cell-active-plan');

function writeJsonAtomic(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temporary = file + '.' + process.pid + '.tmp';
  const fd = fs.openSync(temporary, 'w');
  try {
    fs.writeSync(fd, JSON.stringify(value), null, 'utf8');
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.renameSync(temporary, file);
}

function routePlanOwnerResolver(routePlan) {
  return (entityType, routingId) => {
    if (entityType === 'user') return resolveRoute(routePlan, 'user', routingId);
    if (entityType === 'chat') return resolveRoute(routePlan, 'chat', routingId);
    return null;
  };
}

function cursorKey(cellId, shard) {
  return String(cellId) + ':' + Number(shard);
}

class DualCellNode {
  constructor(options) {
    const opts = options || {};
    const validated = opts.validatedPlan || validateActiveDualCellPlan(opts.plan);
    if (!validated.ok) {
      throw new Error('dual-cell plan is invalid: '
        + validated.failures.map((row) => row.code).join(','));
    }
    this.planResult = validated;
    this.plan = validated.plan;
    const routePlan = opts.routePlan;
    const routeCheck = routePlan && verifyRoutePlan(routePlan);
    if (!routePlan || !routeCheck || !routeCheck.ok) {
      throw new Error('verified route plan is required');
    }
    if (routePlan.hash !== this.plan.routePlanHash) {
      throw new Error('route plan hash does not match dual-cell plan');
    }
    if (routePlan.topologyId !== this.plan.topologyId
        || Number(routePlan.shardCount) !== this.plan.shardCount) {
      throw new Error('route plan topology does not match dual-cell plan');
    }
    this.routePlan = routePlan;
    const requestedCell = String(opts.cell || opts.cellId || '');
    const cellKey = ['a', 'b'].find((key) =>
      key === requestedCell || this.plan.cells[key].id === requestedCell);
    if (!cellKey) throw new Error('unknown dual-cell cell: ' + requestedCell);
    this.cellKey = cellKey;
    this.cell = this.plan.cells[cellKey];
    this.cellId = this.cell.id;
    this.simulatedDataRoot = path.resolve(String(opts.dataRoot || this.cell.dataRoot));
    this.coordinationDir = path.resolve(String(opts.coordinationDir || ''));
    if (!this.coordinationDir) throw new Error('coordinationDir is required');
    this.clusterDir = path.join(this.simulatedDataRoot, 'cluster');
    this.outboxDir = path.join(this.simulatedDataRoot, 'outbox');
    this.cursorFile = path.join(this.simulatedDataRoot, 'replication-cursors.json');
    fs.mkdirSync(this.clusterDir, { recursive: true });
    fs.mkdirSync(this.outboxDir, { recursive: true });
    this.nowNumber = typeof opts.now === 'function' ? opts.now : () => Date.now();
    const ttlMs = Number(this.plan.lease.ttlMs);
    this.cluster = new ShardCluster({
      dataDir: this.clusterDir,
      shardCount: this.plan.shardCount,
      topologyId: this.plan.topologyId,
      ownerResolver: routePlanOwnerResolver(routePlan)
    });
    this.bus = new ShardEventBus({
      dataDir: this.outboxDir,
      shardCount: this.plan.shardCount,
      topologyId: this.plan.topologyId
    });
    this.leases = new ShardLeaseManager({
      dataDir: this.coordinationDir,
      ownerId: this.cellId,
      ttlMs,
      now: this.nowNumber
    });
    let sequence = 0;
    this.gateway = new ShardMutationGateway({
      cluster: this.cluster,
      bus: this.bus,
      leaseManager: this.leases,
      uid: (prefix) => [prefix, this.cellId, process.pid, ++sequence].join('-'),
      now: () => new Date(this.nowNumber()).toISOString()
    });
  }

  activateBaseline() {
    const acquired = [];
    for (const shard of this.cell.ownedShards) {
      acquired.push(this.leases.acquire(shard));
    }
    return {
      cellId: this.cellId,
      acquired: acquired.map((lease) => ({
        shard: lease.shard,
        epoch: lease.epoch
      }))
    };
  }

  takeoverAll() {
    const acquired = [];
    for (let shard = 0; shard < this.plan.shardCount; shard += 1) {
      acquired.push(this.leases.acquire(shard));
    }
    return {
      cellId: this.cellId,
      acquired: acquired.map((lease) => ({
        shard: lease.shard,
        epoch: lease.epoch
      }))
    };
  }

  renewOwnedShards() {
    const renewed = [];
    for (let shard = 0; shard < this.plan.shardCount; shard += 1) {
      const current = this.leases.validate(shard);
      if (current.ok) renewed.push(this.leases.renew(shard));
    }
    return renewed;
  }

  submit(command) {
    const input = command || {};
    let ownerShard;
    try {
      ownerShard = this.cluster.ownerShard(input.entityType, input.entityId);
    } catch (error) {
      return { status: 'invalid', error: String(error.message || error) };
    }
    const lease = this.leases.validate(ownerShard);
    if (!lease.ok || !lease.lease || lease.lease.ownerId !== this.cellId) {
      return {
        status: 'fenced',
        reason: lease.ok ? 'not-cell-owner' : lease.reason,
        ownerShard,
        cellId: this.cellId
      };
    }
    const result = this.gateway.submit(input);
    const critical = this.isCritical(input.entityType);
    return Object.assign({}, result, {
      ownerShard,
      cellId: this.cellId,
      leaseEpoch: lease.lease.epoch,
      critical,
      committed: !critical && result.status === 'applied'
    });
  }

  submitPeerDurable(command, peer) {
    assertSameCellContract(this, peer);
    const result = this.submit(command);
    if (result.status !== 'applied' && result.status !== 'duplicate') return result;
    if (!result.critical) {
      return Object.assign({}, result, {
        status: 'committed',
        committed: true,
        peerReplicated: false
      });
    }
    const rows = [];
    try {
      let row = replicateShard(this, peer, result.ownerShard);
      rows.push(row);
      while (row.lag > 0 && rows.length < 1000) {
        row = replicateShard(this, peer, result.ownerShard);
        rows.push(row);
      }
      if (row.lag !== 0) throw new Error('peer replication did not converge');
    } catch (error) {
      return Object.assign({}, result, {
        status: 'pending-peer',
        committed: false,
        peerReplicated: false,
        replicationError: String(error && error.message || error)
      });
    }
    return Object.assign({}, result, {
      status: 'committed',
      committed: true,
      peerReplicated: true,
      replication: rows
    });
  }

  read(entityType, entityId) {
    return {
      cellId: this.cellId,
      ownerShard: this.cluster.ownerShard(entityType, entityId),
      state: this.cluster.get(entityType, entityId)
    };
  }

  isCritical(entityType) {
    return this.plan.replication.criticalEntityTypes.includes(
      String(entityType || '').toLowerCase()
    );
  }

  loadCursors() {
    try {
      const value = JSON.parse(fs.readFileSync(this.cursorFile, 'utf8'));
      return value && value.cursors && typeof value.cursors === 'object'
        ? value.cursors
        : {};
    } catch (error) {
      if (error && error.code !== 'ENOENT') throw error;
      return {};
    }
  }

  saveCursors(cursors) {
    writeJsonAtomic(this.cursorFile, { version: 1, cursors });
  }

  applyReplicaEvent(event, expectedShard, source) {
    const shard = Number(expectedShard);
    if (!Number.isInteger(shard) || shard < 0 || shard >= this.plan.shardCount) {
      throw new Error('replica shard is out of range');
    }
    if (!event || Number(event.writerShard) !== shard) {
      throw new Error('replica event writer shard mismatch');
    }
    const owner = this.cluster.ownerShard(event.entityType, event.entityId);
    if (owner !== shard) throw new Error('replica event owner shard mismatch');
    const result = this.cluster.log(shard).apply(Object.assign({}, event, {
      topologyId: this.plan.topologyId
    }), { expectedShard: shard });
    if (result.status !== 'applied' && result.status !== 'duplicate') {
      throw new Error('replica apply failed for ' + event.eventId + ': ' + result.status);
    }
    return {
      status: result.status,
      sourceCellId: source.cellId,
      shard,
      eventId: event.eventId
    };
  }

  verify() {
    const verification = this.cluster.verify();
    const eventCounts = [];
    for (let shard = 0; shard < this.plan.shardCount; shard += 1) {
      eventCounts.push(this.cluster.log(shard).eventsById.size);
    }
    return {
      ok: verification.ok,
      cellId: this.cellId,
      eventCounts,
      eventCount: eventCounts.reduce((sum, count) => sum + count, 0),
      verification
    };
  }
}

function assertSameCellContract(source, target) {
  if (!(source instanceof DualCellNode) || !(target instanceof DualCellNode)) {
    throw new Error('replication requires two dual-cell nodes');
  }
  if (source.cellId === target.cellId) throw new Error('replication cells must differ');
  if (source.planResult.hash !== target.planResult.hash
      || source.routePlan.hash !== target.routePlan.hash
      || source.plan.topologyId !== target.plan.topologyId) {
    throw new Error('replication nodes do not share the same frozen plan');
  }
}

function replicateShard(source, target, shard) {
  assertSameCellContract(source, target);
  const index = Number(shard);
  if (!Number.isInteger(index) || index < 0 || index >= source.plan.shardCount) {
    throw new Error('replication shard is out of range');
  }
  const lease = source.leases.validate(index);
  if (!lease.ok || !lease.lease || lease.lease.ownerId !== source.cellId) {
    throw new Error('replication source is not the current owner of shard ' + index);
  }
  const cursors = target.loadCursors();
  const key = cursorKey(source.cellId, index);
  const cursor = Math.max(0, Number(cursors[key]) || 0);
  const events = Array.from(source.cluster.log(index).eventsById.values());
  if (cursor > events.length) {
    throw new Error('replication cursor is beyond source log');
  }
  const batch = events.slice(cursor, cursor + source.plan.replication.batchSize);
  let applied = 0;
  let duplicate = 0;
  for (const event of batch) {
    const result = target.applyReplicaEvent(event, index, source);
    if (result.status === 'applied') applied += 1;
    else duplicate += 1;
  }
  cursors[key] = cursor + batch.length;
  target.saveCursors(cursors);
  return {
    sourceCellId: source.cellId,
    targetCellId: target.cellId,
    shard: index,
    from: cursor,
    to: cursors[key],
    applied,
    duplicate,
    lag: events.length - cursors[key]
  };
}

function replicateOwnedShards(source, target) {
  assertSameCellContract(source, target);
  const rows = [];
  for (let shard = 0; shard < source.plan.shardCount; shard += 1) {
    const lease = source.leases.validate(shard);
    if (!lease.ok || !lease.lease || lease.lease.ownerId !== source.cellId) continue;
    rows.push(replicateShard(source, target, shard));
  }
  return {
    sourceCellId: source.cellId,
    targetCellId: target.cellId,
    shards: rows,
    applied: rows.reduce((sum, row) => sum + row.applied, 0),
    duplicate: rows.reduce((sum, row) => sum + row.duplicate, 0),
    maxLag: rows.reduce((max, row) => Math.max(max, row.lag), 0)
  };
}

function replicationLag(source, target) {
  assertSameCellContract(source, target);
  const cursors = target.loadCursors();
  const rows = [];
  for (let shard = 0; shard < source.plan.shardCount; shard += 1) {
    const lease = source.leases.validate(shard);
    if (!lease.ok || !lease.lease || lease.lease.ownerId !== source.cellId) continue;
    const total = source.cluster.log(shard).eventsById.size;
    const cursor = Math.max(0, Number(cursors[cursorKey(source.cellId, shard)]) || 0);
    rows.push({ shard, total, cursor, lag: Math.max(0, total - cursor) });
  }
  return {
    sourceCellId: source.cellId,
    targetCellId: target.cellId,
    maxLag: rows.reduce((max, row) => Math.max(max, row.lag), 0),
    rows
  };
}

module.exports = {
  DualCellNode,
  replicateShard,
  replicateOwnedShards,
  replicationLag
};
