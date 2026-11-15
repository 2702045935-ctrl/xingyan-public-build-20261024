'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { ShardCluster } = require('../lib/shard-runtime');
const { ShardEventBus } = require('../lib/shard-event-bus');
const { ShardMutationGateway } = require('../lib/shard-gateway');

class FlakyBus {
  constructor(realBus) {
    this.real = realBus;
    this.failuresRemaining = 1;
  }

  publishOnce(event) {
    if (this.failuresRemaining > 0) {
      this.failuresRemaining -= 1;
      throw new Error('simulated event bus outage');
    }
    return this.real.publishOnce(event);
  }

  read(offset, shard) {
    return this.real.read(offset, shard);
  }
}

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-shard-event-outbox-'));
try {
  const firstDataDir = path.join(root, 'cluster');
  const firstCluster = new ShardCluster({
    dataDir: firstDataDir,
    shardCount: 6,
    topologyId: 'server-a-shards-6'
  });
  const firstBus = new ShardEventBus({
    dataDir: firstDataDir,
    shardCount: 6,
    topologyId: 'server-a-shards-6'
  });
  const flakyBus = new FlakyBus(firstBus);
  let uid = 0;
  const firstGateway = new ShardMutationGateway({
    cluster: firstCluster,
    bus: flakyBus,
    uid: (prefix) => prefix + '-outbox-' + (++uid),
    now: () => '2026-11-15T00:00:00.000Z'
  });

  const command = {
    entityType: 'profile',
    entityId: 'outbox-user',
    operation: 'update',
    payload: { nickname: 'Outbox' },
    eventId: 'outbox-event-1'
  };
  let result = firstGateway.submit(command);
  assert.strictEqual(result.status, 'applied');
  assert.strictEqual(result.busPending, true);
  assert.strictEqual(firstCluster.get('profile', 'outbox-user').payload.nickname, 'Outbox');
  assert.strictEqual(firstBus.read(0, result.ownerShard).length, 0);

  result = firstGateway.submit(command);
  assert.strictEqual(result.status, 'duplicate');
  assert.strictEqual(result.busPending, false);
  assert.strictEqual(result.busRepaired, true);
  assert.strictEqual(firstBus.read(0, result.ownerShard).length, 1);

  result = firstGateway.submit(command);
  assert.strictEqual(result.status, 'duplicate');
  assert.strictEqual(result.busRepaired, false);
  assert.strictEqual(firstBus.read(0, result.ownerShard).length, 1);

  const second = firstGateway.submit({
    entityType: 'profile',
    entityId: 'outbox-user',
    operation: 'update',
    payload: { nickname: 'Outbox 2' },
    eventId: 'outbox-event-2'
  });
  assert.strictEqual(second.status, 'applied');
  assert.strictEqual(second.busPending, false);

  assert.throws(() => firstBus.publishOnce({
    eventId: 'outbox-event-1',
    entityType: 'profile',
    entityId: 'outbox-user',
    version: 1,
    writerShard: result.ownerShard,
    topologyId: 'server-a-shards-6',
    payload: { nickname: 'Different' }
  }), /event id conflict/);

  const dataDir = path.join(root, 'repair');
  const cluster = new ShardCluster({
    dataDir,
    shardCount: 6,
    topologyId: 'server-a-shards-6'
  });
  const realBus = new ShardEventBus({
    dataDir,
    shardCount: 6,
    topologyId: 'server-a-shards-6'
  });
  const failingBus = {
    publishOnce() { throw new Error('bus unavailable'); }
  };
  const gateway = new ShardMutationGateway({
    cluster,
    bus: failingBus,
    uid: (prefix) => prefix + '-repair',
    now: () => '2026-11-15T00:00:00.000Z'
  });
  const write = gateway.submit({
    entityType: 'moment',
    entityId: 'repair-moment',
    operation: 'publish',
    payload: { content: 'repair me' },
    eventId: 'repair-event-1'
  });
  assert.strictEqual(write.status, 'applied');
  assert.strictEqual(write.busPending, true);
  const repair = realBus.syncFromCluster(cluster);
  assert.deepStrictEqual(repair, { repaired: 1, events: 1 });
  assert.deepStrictEqual(realBus.syncFromCluster(cluster), { repaired: 0, events: 1 });
  assert.strictEqual(cluster.verify().ok, true);

  console.log('shard-event-outbox: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
