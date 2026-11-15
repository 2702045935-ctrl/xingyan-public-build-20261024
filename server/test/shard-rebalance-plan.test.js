'use strict';

const assert = require('assert');
const { buildShardRebalancePlan } = require('../lib/shard-rebalance-plan');

const assignments = {};
for (let index = 0; index < 6000; index += 1) {
  assignments['c:chat-' + index] = index % 6;
}

const plan = buildShardRebalancePlan({
  sourceShardCount: 6,
  targetShardCount: 7,
  targetTopologyId: 'server-a-shards-7',
  assignments
});

assert.strictEqual(plan.ok, true, JSON.stringify(plan.failures));
assert.strictEqual(plan.total, 6000);
assert.strictEqual(plan.sourceShardCount, 6);
assert.strictEqual(plan.targetShardCount, 7);
assert.ok(plan.moveCount > 700 && plan.moveCount < 1000);
assert.ok(plan.movePct > 11 && plan.movePct < 17);
assert.strictEqual(plan.after[6], Math.round(6000 / 7));
assert.ok(plan.maxDeviation < 0.01);
assert.match(plan.fingerprint, /^[a-f0-9]{64}$/);
assert.match(plan.moveDigest, /^[a-f0-9]{64}$/);
assert.strictEqual(Object.keys(plan.assignments).length, 6000);
assert.strictEqual(plan.moves.length, plan.moveCount);
for (const move of plan.moves) {
  assert.strictEqual(assignments[move.key], move.from);
  assert.strictEqual(plan.assignments[move.key], move.to);
  assert.ok(move.to >= 6 && move.to < 7);
}

const repeated = buildShardRebalancePlan({
  sourceShardCount: 6,
  targetShardCount: 7,
  targetTopologyId: 'server-a-shards-7',
  assignments
});
assert.strictEqual(repeated.fingerprint, plan.fingerprint);
assert.deepStrictEqual(repeated.moves, plan.moves);

const invalid = buildShardRebalancePlan({
  sourceShardCount: 6,
  targetShardCount: 5,
  targetTopologyId: 'shrink',
  assignments
});
assert.strictEqual(invalid.ok, false);
assert.ok(invalid.failures.some((row) => row.code === 'target-shard-count'));

console.log('shard-rebalance-plan: passed');
