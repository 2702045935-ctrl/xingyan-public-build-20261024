'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { buildRoutePlan, resolveRoute } = require('./shard-route-plan');
const {
  DualCellNode,
  replicateShard,
  replicateOwnedShards,
  replicationLag
} = require('./dual-cell-replication');

function makeRoutePlan() {
  const users = Array.from({ length: 160 }, (_, index) => ({
    id: 'drill-user-' + String(index).padStart(3, '0')
  }));
  return buildRoutePlan({
    users,
    chats: [],
    shardCount: 7,
    ports: [7080, 7180, 7280, 7380, 7480, 7580, 7680],
    topologyId: 'dual-cell-drill-shards-7',
    baselineDate: '2026-11-17',
    createdAt: '2026-11-17T00:00:00Z'
  });
}

function pickUserByShard(routePlan) {
  const rows = Array.from({ length: 7 }, () => '');
  for (const entry of routePlan.assignments ? Object.keys(routePlan.assignments) : []) {
    if (!entry.startsWith('u:')) continue;
    const id = entry.slice(2);
    const shard = resolveRoute(routePlan, 'user', id);
    if (!rows[shard]) rows[shard] = id;
  }
  for (let shard = 0; shard < rows.length; shard += 1) {
    if (!rows[shard]) throw new Error('drill fixture did not cover shard ' + shard);
  }
  return rows;
}

function makePlan(routePlan, root) {
  return {
    version: 1,
    mode: 'active-active',
    topologyId: routePlan.topologyId,
    routePlanHash: routePlan.hash,
    shardCount: routePlan.shardCount,
    activation: {
      trafficMode: 'dormant',
      canaryPercent: 0,
      writesEnabled: false
    },
    cells: {
      a: {
        id: 'cell-a',
        host: 'cell-a.example',
        role: 'active',
        failureDomain: 'drill-zone-a',
        dataRoot: path.join(root, 'cell-a'),
        baseUrl: 'https://cell-a.example:5443',
        ownedShards: [0, 1, 2, 3]
      },
      b: {
        id: 'cell-b',
        host: 'cell-b.example',
        role: 'active',
        failureDomain: 'drill-zone-b',
        dataRoot: path.join(root, 'cell-b'),
        baseUrl: 'https://cell-b.example:5443',
        ownedShards: [4, 5, 6]
      }
    },
    lease: {
      authority: 'external-consensus',
      ttlMs: 10000,
      renewalMs: 1000,
      fencing: 'epoch'
    },
    replication: {
      transport: 'https',
      delivery: 'durable-outbox',
      standardAck: 'owner-durable-outbox',
      criticalAck: 'peer-durable-outbox',
      criticalEntityTypes: ['transfer', 'payment', 'ledger', 'balance'],
      batchSize: 50,
      peerTimeoutMs: 1000
    },
    gateway: {
      writeMode: 'lease-owner-only',
      readMode: 'local-replica',
      rejectStaleOwner: true
    }
  };
}

function runDualCellFailoverDrill() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-dual-cell-drill-'));
  let clock = 1000;
  const now = () => clock;
  try {
    const routePlan = makeRoutePlan();
    const users = pickUserByShard(routePlan);
    const coordinationDir = path.join(root, 'coordination');
    const plan = makePlan(routePlan, root);
    const nodeA = new DualCellNode({
      plan,
      routePlan,
      cell: 'a',
      dataRoot: path.join(root, 'cell-a'),
      coordinationDir,
      now
    });
    const nodeB = new DualCellNode({
      plan,
      routePlan,
      cell: 'b',
      dataRoot: path.join(root, 'cell-b'),
      coordinationDir,
      now
    });
    const activationA = nodeA.activateBaseline();
    const activationB = nodeB.activateBaseline();

    const seedIds = [];
    for (let shard = 0; shard < 7; shard += 1) {
      const owner = shard < 4 ? nodeA : nodeB;
      const replica = shard < 4 ? nodeB : nodeA;
      const userId = users[shard];
      for (let version = 1; version <= 3; version += 1) {
        const eventId = 'seed-' + shard + '-' + version;
        const result = owner.submit({
          entityType: 'user',
          entityId: userId,
          operation: 'update',
          payload: { shard, version },
          eventId
        });
        if (result.status !== 'applied') {
          throw new Error('seed write failed: ' + JSON.stringify(result));
        }
        seedIds.push(eventId);
        replicateShard(owner, replica, shard);
      }
    }
    replicateOwnedShards(nodeA, nodeB);
    replicateOwnedShards(nodeB, nodeA);

    const critical = nodeA.submitPeerDurable({
      entityType: 'transfer',
      entityId: 'drill-transfer-1',
      operation: 'claim',
      payload: { amount: '10.00', currency: 'CNY' },
      eventId: 'critical-transfer-1'
    }, nodeB);
    if (critical.status !== 'committed') {
      throw new Error('critical write failed: ' + JSON.stringify(critical));
    }
    const criticalReplication = critical.replication[0];
    const duplicate = nodeA.submit({
      entityType: 'transfer',
      entityId: 'drill-transfer-1',
      operation: 'claim',
      payload: { amount: '10.00', currency: 'CNY' },
      eventId: 'critical-transfer-1'
    });
    const wrongCell = nodeB.submit({
      entityType: 'user',
      entityId: users[0],
      operation: 'update',
      payload: { stale: true },
      eventId: 'wrong-cell-write'
    });

    const lagBeforeFailover = replicationLag(nodeA, nodeB);
    const lagBeforeFailoverB = replicationLag(nodeB, nodeA);
    clock = 11001;
    const takeoverB = nodeB.takeoverAll();
    const staleA = nodeA.submit({
      entityType: 'user',
      entityId: users[0],
      operation: 'update',
      payload: { stale: true },
      eventId: 'stale-a-after-takeover'
    });
    const failoverWrite = nodeB.submit({
      entityType: 'user',
      entityId: users[0],
      operation: 'update',
      payload: { owner: 'cell-b', epoch: 2 },
      eventId: 'cell-b-after-takeover'
    });
    const failoverReplication = replicateShard(nodeB, nodeA, 0);

    clock = 22002;
    const takeoverA = nodeA.takeoverAll();
    const staleB = nodeB.submit({
      entityType: 'user',
      entityId: users[4],
      operation: 'update',
      payload: { stale: true },
      eventId: 'stale-b-after-takeover'
    });
    const failbackWrite = nodeA.submit({
      entityType: 'user',
      entityId: users[4],
      operation: 'update',
      payload: { owner: 'cell-a', epoch: 3 },
      eventId: 'cell-a-after-failback'
    });
    const failbackReplication = replicateShard(nodeA, nodeB, 4);
    replicateOwnedShards(nodeA, nodeB);
    replicateOwnedShards(nodeB, nodeA);

    const finalA = nodeA.verify();
    const finalB = nodeB.verify();
    const eventIdsA = [];
    const eventIdsB = [];
    for (let shard = 0; shard < 7; shard += 1) {
      eventIdsA.push(...nodeA.cluster.log(shard).eventsById.keys());
      eventIdsB.push(...nodeB.cluster.log(shard).eventsById.keys());
    }
    const sortedA = eventIdsA.slice().sort();
    const sortedB = eventIdsB.slice().sort();
    const checks = {
      baselineOwnersDisjoint: activationA.acquired.length === 4
        && activationB.acquired.length === 3,
      seedEventsApplied: seedIds.length === 21,
      criticalReplicatedBeforeCommit: criticalReplication.applied === 1,
      duplicateIsIdempotent: duplicate.status === 'duplicate',
      wrongCellFenced: wrongCell.status === 'fenced',
      replicasCaughtUp: lagBeforeFailover.maxLag === 0
        && lagBeforeFailoverB.maxLag === 0,
      failoverEpochAdvanced: takeoverB.acquired.some((row) => row.shard === 0 && row.epoch === 2),
      staleOwnerFenced: staleA.status === 'fenced',
      failoverWriteApplied: failoverWrite.status === 'applied'
        && Number(failoverWrite.leaseEpoch) === 2,
      recoveredReplicaAccepted: failoverReplication.applied === 1,
      failbackEpochAdvanced: takeoverA.acquired.some((row) => row.shard === 4 && row.epoch === 3),
      oldSecondaryOwnerFenced: staleB.status === 'fenced',
      failbackWriteApplied: failbackWrite.status === 'applied'
        && Number(failbackWrite.leaseEpoch) === 3,
      finalReplicasEqual: JSON.stringify(sortedA) === JSON.stringify(sortedB),
      noMissingEvents: sortedA.length === 24,
      noDuplicateEvents: new Set(sortedA).size === sortedA.length,
      bothClustersVerified: finalA.ok === true && finalB.ok === true
    };
    const failed = Object.keys(checks).filter((key) => checks[key] !== true);
    return {
      version: 1,
      scope: 'system-temporary-directory',
      okayToActivateTraffic: false,
      reason: 'This drill proves ownership and replication mechanics only; it is not a production canary.',
      topologyId: routePlan.topologyId,
      routePlanHash: routePlan.hash,
      owners: {
        a: [0, 1, 2, 3],
        b: [4, 5, 6]
      },
      eventCount: sortedA.length,
      finalEventIds: sortedA,
      checks,
      ok: failed.length === 0,
      failures: failed
    };
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
}

module.exports = {
  makeRoutePlan,
  pickUserByShard,
  makePlan,
  runDualCellFailoverDrill
};
