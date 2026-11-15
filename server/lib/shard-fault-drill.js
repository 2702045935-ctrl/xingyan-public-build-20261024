'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { ShardCluster } = require('./shard-runtime');
const { ShardEventBus } = require('./shard-event-bus');
const { ShardMutationGateway } = require('./shard-gateway');
const { ShardLeaseManager } = require('./shard-lease');

class DrillBus {
  constructor(realBus) {
    this.realBus = realBus;
    this.failOnce = new Set();
    this.failAlways = new Set();
    this.delayMs = 0;
  }

  publishOnce(event) {
    if (this.delayMs > 0) {
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, this.delayMs);
    }
    if (this.failAlways.has(event.eventId)) {
      throw new Error('simulated persistent event bus outage');
    }
    if (this.failOnce.has(event.eventId)) {
      this.failOnce.delete(event.eventId);
      throw new Error('simulated transient event bus outage');
    }
    return this.realBus.publishOnce(event);
  }
}

function runShardFaultDrill() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-shard-fault-drill-'));
  const topologyId = 'drill-shards-7';
  let clock = 1000;
  const now = () => clock;
  try {
    const dataDir = path.join(root, 'cluster');
    const cluster = new ShardCluster({
      dataDir,
      shardCount: 7,
      topologyId
    });
    const realBus = new ShardEventBus({
      dataDir,
      shardCount: 7,
      topologyId
    });
    const drillBus = new DrillBus(realBus);
    const leaseA = new ShardLeaseManager({
      dataDir,
      ownerId: 'node-a',
      ttlMs: 1000,
      now
    });
    const leaseB = new ShardLeaseManager({
      dataDir,
      ownerId: 'node-b',
      ttlMs: 1000,
      now
    });
    for (let shard = 0; shard < 7; shard += 1) leaseA.acquire(shard);

    let sequence = 0;
    const gatewayA = new ShardMutationGateway({
      cluster,
      bus: drillBus,
      leaseManager: leaseA,
      uid: (prefix) => prefix + '-a-' + (++sequence),
      now: () => new Date(clock).toISOString()
    });
    const entity = {
      entityType: 'profile',
      entityId: 'drill-profile'
    };
    const ownerShard = cluster.ownerShard(entity.entityType, entity.entityId);
    const first = gatewayA.submit(Object.assign({}, entity, {
      operation: 'update',
      payload: { nickname: 'alice-1' },
      eventId: 'drill-event-1'
    }));

    clock = 2101;
    const expired = leaseA.validate(ownerShard);
    const leaseEpochB = leaseB.acquire(ownerShard).epoch;
    const fenced = gatewayA.submit(Object.assign({}, entity, {
      operation: 'update',
      payload: { nickname: 'stale-writer' },
      eventId: 'drill-event-stale'
    }));

    const gatewayB = new ShardMutationGateway({
      cluster,
      bus: drillBus,
      leaseManager: leaseB,
      uid: (prefix) => prefix + '-b-' + (++sequence),
      now: () => new Date(clock).toISOString()
    });
    const secondCommand = Object.assign({}, entity, {
      operation: 'update',
      payload: { nickname: 'alice-2' },
      eventId: 'drill-event-2',
      expectedVersion: 1
    });
    drillBus.failOnce.add(secondCommand.eventId);
    const pendingSecond = gatewayB.submit(secondCommand);
    const repairedSecond = gatewayB.submit(secondCommand);

    drillBus.failAlways.add('drill-event-3');
    const pendingThird = gatewayB.submit(Object.assign({}, entity, {
      operation: 'update',
      payload: { nickname: 'alice-3' },
      eventId: 'drill-event-3',
      expectedVersion: 2
    }));
    const repair = realBus.syncFromCluster(cluster);

    const reopened = new ShardCluster({
      dataDir,
      shardCount: 7,
      topologyId
    });
    const verification = reopened.verify();
    const current = reopened.get(entity.entityType, entity.entityId);
    const busEvents = [];
    for (let shard = 0; shard < 7; shard += 1) busEvents.push(...realBus.read(0, shard));
    const eventIds = new Set(busEvents.map((event) => event.eventId));

    const checks = {
      initialWriteApplied: first.status === 'applied',
      oldLeaseExpired: expired.ok === false && expired.reason === 'expired',
      failoverEpochAdvanced: leaseEpochB === 2,
      staleWriterFenced: fenced.status === 'fenced',
      failoverWriteApplied: pendingSecond.status === 'applied',
      transientOutageReported: pendingSecond.busPending === true,
      duplicateRetryRepairedBus: repairedSecond.status === 'duplicate'
        && repairedSecond.busRepaired === true,
      persistentOutageReported: pendingThird.status === 'applied'
        && pendingThird.busPending === true,
      reconciliationRepairedExactlyOnce: repair.repaired === 1,
      finalVersion: Number(current && current.version) === 3,
      finalPayload: current && current.payload && current.payload.nickname === 'alice-3',
      finalWriterEpoch: Number(current && current.writerEpoch) === 2,
      staleWriteAbsent: !busEvents.some((event) => event.eventId === 'drill-event-stale'),
      eventCount: busEvents.length === 3,
      uniqueEventIds: eventIds.size === 3,
      clusterVerifiedAfterRestart: verification.ok === true
    };
    const failed = Object.keys(checks).filter((key) => checks[key] !== true);
    return {
      version: 1,
      generatedAt: new Date().toISOString(),
      scope: 'system-temporary-directory',
      topologyId,
      ownerShard,
      leaseEpochB,
      repair,
      eventIds: Array.from(eventIds).sort(),
      checks,
      ok: failed.length === 0,
      failures: failed
    };
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
}

module.exports = { runShardFaultDrill };
