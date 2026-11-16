'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { buildRoutePlan, resolveRoute } = require('../lib/shard-route-plan');
const { loadChatRoutePlan, chatOwnerShard } = require('../lib/chat-route-plan');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-chat-route-plan-'));
const file = path.join(root, 'route-plan.json');
const ports = [7080, 7180, 7280, 7380, 7480, 7580, 7680];

try {
  const plan = buildRoutePlan({
    users: [{ id: 'u1' }, { id: 'u2' }],
    chats: [{ id: 'c1' }, { id: 'c2' }],
    shardCount: 7,
    ports,
    topologyId: 'server-b-mainline-shards-7',
    baselineDate: '2026-11-16',
    createdAt: '2026-11-16T00:00:00Z'
  });
  fs.writeFileSync(file, JSON.stringify(plan));
  const runtime = { shardCount: 7, basePort: 7080, shardId: 0, port: 7080 };
  const loaded = loadChatRoutePlan(file, runtime);
  assert.ok(loaded);
  assert.strictEqual(loaded.hash, plan.hash);
  assert.strictEqual(loaded.topologyId, plan.topologyId);
  assert.strictEqual(chatOwnerShard(loaded, 'c1', 7), resolveRoute(plan, 'chat', 'c1'));
  assert.throws(
    () => loadChatRoutePlan(file, Object.assign({}, runtime, { basePort: 7000 })),
    /ports mismatch/
  );
  assert.throws(
    () => loadChatRoutePlan(file, Object.assign({}, runtime, { port: 7180 })),
    /runtime port mismatch/
  );
  assert.throws(
    () => loadChatRoutePlan(file, Object.assign({}, runtime, { shardId: 7 })),
    /SHARD_ID is invalid/
  );
  const bad = JSON.parse(JSON.stringify(plan));
  bad.assignments['c:c1'] = (bad.assignments['c:c1'] + 1) % 7;
  fs.writeFileSync(file, JSON.stringify(bad));
  assert.throws(
    () => loadChatRoutePlan(file, runtime),
    /verification failed/
  );
  console.log('chat-route-plan: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
