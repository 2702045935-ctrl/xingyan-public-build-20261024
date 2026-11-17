'use strict';

const assert = require('assert');
const { validateActiveDualCellPlan } = require('../lib/dual-cell-active-plan');
const { DualCellLeaseAgent } = require('../lib/dual-cell-lease-agent');

const plan = {
  version: 1,
  mode: 'active-active',
  topologyId: 'lease-agent-test',
  routePlanHash: 'a'.repeat(64),
  shardCount: 7,
  activation: { trafficMode: 'dormant', canaryPercent: 0, writesEnabled: false },
  cells: {
    a: {
      id: 'cell-a', host: 'cell-a.example', role: 'active', failureDomain: 'zone-a',
      dataRoot: '/srv/a', baseUrl: 'https://cell-a.example:5443', ownedShards: [0, 1, 2, 3]
    },
    b: {
      id: 'cell-b', host: 'cell-b.example', role: 'active', failureDomain: 'zone-b',
      dataRoot: '/srv/b', baseUrl: 'https://cell-b.example:5443', ownedShards: [4, 5, 6]
    }
  },
  lease: { authority: 'external-consensus', ttlMs: 30000, renewalMs: 5000, fencing: 'epoch' },
  replication: {
    transport: 'https', delivery: 'durable-outbox', standardAck: 'owner-durable-outbox',
    criticalAck: 'peer-durable-outbox', criticalEntityTypes: ['transfer'],
    batchSize: 10, peerTimeoutMs: 1000
  },
  gateway: { writeMode: 'lease-owner-only', readMode: 'local-replica', rejectStaleOwner: true }
};
const validated = validateActiveDualCellPlan(plan);
assert.strictEqual(validated.ok, true, JSON.stringify(validated.failures));

const calls = [];
let lost = null;
const fakeLease = {
  async acquire(shard) { calls.push(['acquire', shard]); return { shard, epoch: 1 }; },
  async renew(shard) { calls.push(['renew', shard]); return { shard, epoch: 1 }; },
  async release(shard) { calls.push(['release', shard]); return true; }
};

async function main() {
  const agent = new DualCellLeaseAgent({
    validatedPlan: validated,
    cell: 'a',
    leaseManager: fakeLease,
    intervalMs: 5000,
    onLost: (row) => { lost = row; }
  });
  const started = await agent.start();
  assert.deepStrictEqual(started.ownedShards, [0, 1, 2, 3]);
  await agent.renewOnce();
  assert.deepStrictEqual(calls.slice(4, 8).map((row) => row[0]), [
    'renew', 'renew', 'renew', 'renew'
  ]);
  await agent.stop();
  assert.strictEqual(agent.status().active, false);

  let failRenew = false;
  const losingLease = Object.assign({}, fakeLease, {
    async renew(shard) {
      if (failRenew) throw new Error('lease lost');
      return { shard, epoch: 1 };
    }
  });
  const losing = new DualCellLeaseAgent({
    validatedPlan: validated,
    cell: 'b',
    leaseManager: losingLease,
    intervalMs: 5000,
    onLost: (row) => { lost = row; }
  });
  await losing.start();
  failRenew = true;
  await assert.rejects(() => losing.renewOnce(), /lease lost/);
  assert.strictEqual(losing.status().active, false);
  assert.strictEqual(lost.shard, 4);
  console.log('dual-cell-lease-agent: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
