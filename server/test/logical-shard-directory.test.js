'use strict';

const assert = require('assert');
const {
  buildLogicalShardDirectory,
  validateDirectoryTransition,
  logicalShardForKey,
  lookup
} = require('../lib/logical-shard-directory');

const four = buildLogicalShardDirectory({
  topologyId: 'future-4096-four-cell',
  routingNamespace: 'xingyan-future-route-v1',
  logicalShardCount: 4096,
  cells: [
    { id: 'a', host: '10.0.0.1', weight: 1, replicaCount: 2 },
    { id: 'b', host: '10.0.0.2', weight: 1, replicaCount: 2 },
    { id: 'c', host: '10.0.0.3', weight: 1, replicaCount: 2 },
    { id: 'd', host: '10.0.0.4', weight: 1, replicaCount: 2 }
  ]
});
assert.strictEqual(four.ok, true, JSON.stringify(four.failures));
assert.strictEqual(four.shards.length, 4096);
assert.strictEqual(Object.values(four.coverage).reduce((sum, value) => sum + value, 0), 4096);
assert.ok(four.maxDeviation < 0.12, String(four.maxDeviation));
assert.deepStrictEqual(
  new Set(four.cells.map((cell) => cell.id)),
  new Set(Object.keys(four.coverage))
);
assert.ok(four.shards.every((shard) =>
  shard.replicas.length >= 2
  && !shard.replicas.includes(shard.primary)
  && new Set(shard.replicas).size === shard.replicas.length
));

const keys = ['user:1', 'chat:1', 'user:999999', 'chat:999999'];
const before = keys.map((key) => lookup(four, key));
assert.deepStrictEqual(
  keys.map((key) => logicalShardForKey(four, key)),
  keys.map((key) => logicalShardForKey(four, key))
);

const eight = buildLogicalShardDirectory({
  topologyId: 'future-4096-eight-cell',
  routingNamespace: 'xingyan-future-route-v1',
  logicalShardCount: 4096,
  cells: ['e', 'f', 'g', 'h'].reduce((cells) => {
    cells.push({
      id: String.fromCharCode(cells.length + 97),
      host: '10.0.1.' + (cells.length + 1),
      weight: 1,
      replicaCount: 2
    });
    return cells;
  }, four.cells.map((cell) => Object.assign({}, cell)))
});
const after = keys.map((key) => lookup(eight, key));
assert.deepStrictEqual(after.map((row) => row.logicalShard),
  before.map((row) => row.logicalShard));
assert.ok(after.some((row, index) => row.primary !== before[index].primary));
assert.strictEqual(validateDirectoryTransition(four, eight).ok, true);

const changed = buildLogicalShardDirectory({
  topologyId: 'future-4096-four-cell',
  routingNamespace: 'xingyan-future-route-v1',
  logicalShardCount: 8192,
  cells: four.cells
});
assert.ok(validateDirectoryTransition(four, changed).failures.some((row) =>
  row.code === 'logical-shard-count-changed'));

console.log('logical-shard-directory: passed');
