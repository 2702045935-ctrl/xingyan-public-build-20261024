'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { validateActiveDualCellPlan } = require('../lib/dual-cell-active-plan');

const valid = {
  version: 1,
  mode: 'active-active',
  topologyId: 'dual-cell-test-shards-7',
  routePlanHash: 'a'.repeat(64),
  shardCount: 7,
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
      failureDomain: 'zone-a',
      dataRoot: '/srv/xingyan/cell-a',
      baseUrl: 'https://cell-a.example:5443',
      ownedShards: [0, 1, 2, 3]
    },
    b: {
      id: 'cell-b',
      host: 'cell-b.example',
      role: 'active',
      failureDomain: 'zone-b',
      dataRoot: '/srv/xingyan/cell-b',
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
    criticalEntityTypes: ['transfer', 'ledger'],
    batchSize: 100,
    peerTimeoutMs: 1000
  },
  gateway: {
    writeMode: 'lease-owner-only',
    readMode: 'local-replica',
    rejectStaleOwner: true
  }
};

const accepted = validateActiveDualCellPlan(valid);
assert.strictEqual(accepted.ok, true, JSON.stringify(accepted.failures));
assert.match(accepted.hash, /^[a-f0-9]{64}$/);
assert.deepStrictEqual(accepted.plan.cells.a.ownedShards, [0, 1, 2, 3]);
assert.deepStrictEqual(accepted.shardOwners, ['a', 'a', 'a', 'a', 'b', 'b', 'b']);

const missingShard = JSON.parse(JSON.stringify(valid));
missingShard.cells.b.ownedShards = [4, 5];
assert.ok(validateActiveDualCellPlan(missingShard).failures.some(
  (row) => row.code === 'shard-unowned'
));

const duplicateShard = JSON.parse(JSON.stringify(valid));
duplicateShard.cells.b.ownedShards = [3, 4, 5, 6];
assert.ok(validateActiveDualCellPlan(duplicateShard).failures.some(
  (row) => row.code === 'shard-multi-owner'
));

const sharedHost = JSON.parse(JSON.stringify(valid));
sharedHost.cells.b.host = valid.cells.a.host;
assert.ok(validateActiveDualCellPlan(sharedHost).failures.some(
  (row) => row.code === 'cell-host-shared'
));

const sharedDomain = JSON.parse(JSON.stringify(valid));
sharedDomain.cells.b.failureDomain = valid.cells.a.failureDomain;
assert.ok(validateActiveDualCellPlan(sharedDomain).failures.some(
  (row) => row.code === 'failure-domain-shared'
));

const dormantWrites = JSON.parse(JSON.stringify(valid));
dormantWrites.activation.writesEnabled = true;
assert.ok(validateActiveDualCellPlan(dormantWrites).failures.some(
  (row) => row.code === 'dormant-must-be-write-disabled'
));

const unsafeAck = JSON.parse(JSON.stringify(valid));
unsafeAck.replication.criticalAck = 'owner-durable-outbox';
assert.ok(validateActiveDualCellPlan(unsafeAck).failures.some(
  (row) => row.code === 'critical-ack'
));

const candidateFile = path.join(__dirname, '..', '..', 'docs', 'DUAL_CELL_ACTIVE_PLAN.candidate.json');
const candidate = validateActiveDualCellPlan(JSON.parse(fs.readFileSync(candidateFile, 'utf8')));
assert.strictEqual(candidate.ok, true, JSON.stringify(candidate.failures));
assert.match(candidate.plan.cells.a.failureDomain, /^UNVERIFIED-/);
assert.match(candidate.plan.cells.b.failureDomain, /^UNVERIFIED-/);
assert.strictEqual(candidate.plan.activation.writesEnabled, false);

console.log('dual-cell-active-plan: passed');
