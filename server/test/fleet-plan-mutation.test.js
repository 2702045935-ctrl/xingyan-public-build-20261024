'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {
  addNode,
  deleteNode,
  rebalanceOwners
} = require('../lib/fleet-plan-mutation');
const { validateFleetPlan } = require('../lib/fleet-release-plan');

const root = path.resolve(__dirname, '..', '..');
const source = JSON.parse(fs.readFileSync(
  path.join(root, 'deploy', 'fleet', 'fleet-production.json'),
  'utf8'
));

function node() {
  return {
    id: 'cell-c-203',
    host: '192.0.2.30',
    failureDomain: 'provider-c-zone-a',
    servicePrefix: 'xingyan-dual-cell-c',
    dataRoot: '/opt/xingyan-dual-cell/physical-r1/stage/shards',
    ports: [21080, 21180, 21280, 21380, 21480, 21580, 21680]
  };
}

const expanded = addNode(source, node());
assert.strictEqual(validateFleetPlan(expanded).ok, true);
assert.strictEqual(expanded.cells.length, 3);
assert.deepStrictEqual(
  expanded.cells.find((cell) => cell.id === 'cell-c-203').replicaShards,
  [0, 1, 2, 3, 4, 5, 6]
);
for (let shard = 0; shard < expanded.shardCount; shard += 1) {
  assert.strictEqual(expanded.cells.filter((cell) =>
    cell.ownerShards.includes(shard)).length, 1);
}

const shrunk = deleteNode(expanded, 'cell-c-203');
assert.strictEqual(validateFleetPlan(shrunk).ok, true);
assert.strictEqual(shrunk.cells.length, 2);
assert.ok(!shrunk.cells.some((cell) => cell.id === 'cell-c-203'));
assert.strictEqual(validateFleetPlan(shrunk).ok, true);

const balanced = rebalanceOwners(source);
assert.strictEqual(validateFleetPlan(balanced).ok, true);
assert.strictEqual(
  balanced.cells.reduce((sum, cell) => sum + cell.ownerShards.length, 0),
  source.shardCount
);
assert.throws(() => deleteNode({
  version: 1,
  topologyId: 'one',
  routePlanHash: 'a'.repeat(64),
  routePlanFileSha256: 'b'.repeat(64),
  shardCount: 1,
  release: { id: 'test', codeSha256: 'c'.repeat(64) },
  policy: {
    maxOwnerShardsInFlight: 1,
    requireReplicaCaughtUp: true,
    requireCapacityReport: true,
    requireHealthGate: true,
    autoRollback: true
  },
  cells: [{
    id: 'only', host: '192.0.2.1', failureDomain: 'zone-a',
    servicePrefix: 'only', dataRoot: '/tmp/only',
    replicaShards: [0], ownerShards: [0], ports: [8080]
  }]
}, 'only'), /last cell/);

console.log('fleet-plan-mutation: passed');
