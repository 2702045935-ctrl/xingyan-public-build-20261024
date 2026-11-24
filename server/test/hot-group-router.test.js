'use strict';

const assert = require('assert');
const { HotGroupRouter } = require('../lib/hot-group-router');

function main() {
  const router = new HotGroupRouter({
    threshold: 512,
    maxBatch: 512,
    cellCount: 7
  });
  const members = Array.from({ length: 10_000 }, (_, i) => `u-${i}`);
  const nodes = Array.from({ length: 32 }, (_, i) => `gw-${i}`);
  const plan = router.plan({ chatId: 'group-hot', memberIds: members, nodeIds: nodes });
  assert.equal(plan.mode, 'dedicated-cell');
  assert.equal(plan.memberCount, 10_000);
  assert.ok(plan.partition >= 0 && plan.partition < 7);
  assert.ok(plan.batches.length >= 32);
  const delivered = new Set();
  plan.batches.forEach((batch) => {
    assert.ok(batch.userIds.length <= 512);
    batch.userIds.forEach((id) => {
      assert.equal(delivered.has(id), false);
      delivered.add(id);
    });
  });
  assert.equal(delivered.size, 10_000);
  assert.equal(router.classify({ memberIds: ['a', 'b'] }, {}), 'local');
  console.log('hot-group-router: passed');
}

main();
