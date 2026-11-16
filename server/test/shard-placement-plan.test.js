'use strict';

const assert = require('assert');
const { buildPlacementPlan } = require('../lib/shard-placement-plan');
const { buildRoutePlan } = require('../lib/shard-route-plan');

const users = [{ id: 'u1' }, { id: 'u2' }];
const chats = [{ id: 'c1' }];
const routePlan = buildRoutePlan({
  users,
  chats,
  shardCount: 7,
  ports: [7080, 7180, 7280, 7380, 7480, 7580, 7680],
  topologyId: 'server-b-mainline-shards-7',
  baselineDate: '2026-11-16',
  createdAt: '2026-11-16T00:00:00Z'
});
const plan = buildPlacementPlan({
  routePlan,
  data: {
    users,
    friendships: [{ id: 'f1', fromId: 'u1', toId: 'u2' }],
    chats,
    reads: { u1: { c1: 3 } },
    friendMeta: { u1: { u2: { remark: 'B' } } },
    moments: [{
      id: 'm1',
      comments: [{ id: 'mc1', likes: [{ userId: 'u2' }] }],
      likes: [{ userId: 'u2' }]
    }],
    momentNotices: [{ id: 'n1' }],
    messageThreads: ['c1']
  }
});

assert.strictEqual(plan.ok, true, JSON.stringify(plan.failures));
assert.strictEqual(plan.itemCount, 12);
assert.strictEqual(plan.byType.user, 2);
assert.strictEqual(plan.byType.chat, 1);
assert.strictEqual(plan.byType.message_thread, 1);
assert.strictEqual(plan.byShard.reduce((sum, row) => sum + row.total, 0), plan.itemCount);
assert.match(plan.hash, /^[a-f0-9]{64}$/);

console.log('shard-placement-plan: passed');
