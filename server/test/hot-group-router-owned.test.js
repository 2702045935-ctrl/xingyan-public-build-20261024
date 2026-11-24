'use strict';

const assert = require('assert');
const { HotGroupRouter } = require('../lib/hot-group-router');

function main() {
  const router = new HotGroupRouter({ maxBatch: 2, cellCount: 7 });
  const plan = router.planOwned({
    chatId: 'group-owned',
    assignments: {
      'gw-b': ['u3', 'u4', 'u3'],
      'gw-a': ['u1', 'u2', 'u5'],
      '': ['ignored']
    }
  });
  assert.equal(plan.mode, 'owned-batched-cell');
  assert.equal(plan.memberCount, 5);
  assert.equal(plan.nodeCount, 2);
  assert.deepStrictEqual(plan.batches.map((batch) => ({
    nodeId: batch.nodeId,
    userIds: batch.userIds
  })), [
    { nodeId: 'gw-a', userIds: ['u1', 'u2'] },
    { nodeId: 'gw-a', userIds: ['u5'] },
    { nodeId: 'gw-b', userIds: ['u3', 'u4'] }
  ]);
  const ids = plan.batches.flatMap((batch) => batch.userIds);
  assert.deepStrictEqual(ids.slice().sort(), ['u1', 'u2', 'u3', 'u4', 'u5']);
  console.log('hot-group-owned-routing: passed');
}

main();
