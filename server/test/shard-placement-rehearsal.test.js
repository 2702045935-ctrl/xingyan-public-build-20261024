'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { buildRoutePlan } = require('../lib/shard-route-plan');
const { rehearseShardPlacement } = require('../lib/shard-placement-rehearsal');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-placement-rehearsal-'));
const source = path.join(root, 'source');
const stage = path.join(root, 'stage');
const rehydrate = path.join(root, 'rehydrate');
fs.mkdirSync(path.join(source, 'messages'), { recursive: true });

try {
  const users = [{ id: 'u1' }, { id: 'u2' }];
  const chats = [{ id: 'c1', memberIds: ['u1', 'u2'] }];
  fs.writeFileSync(path.join(source, 'users.json'), JSON.stringify({ users }));
  fs.writeFileSync(path.join(source, 'friendships.json'), JSON.stringify({
    friendships: [{ id: 'f1', fromId: 'u1', toId: 'u2' }]
  }));
  fs.writeFileSync(path.join(source, 'chats.json'), JSON.stringify({ chats }));
  fs.writeFileSync(path.join(source, 'reads.json'), JSON.stringify({
    reads: { u1: { c1: 2 } }
  }));
  fs.writeFileSync(path.join(source, 'friendmeta.json'), JSON.stringify({
    byOwner: { u1: { u2: { remark: 'B' } } }
  }));
  fs.writeFileSync(path.join(source, 'moments.json'), JSON.stringify({
    moments: [{ id: 'm1', authorId: 'u1' }]
  }));
  fs.writeFileSync(path.join(source, 'moment-notices.json'), JSON.stringify({
    items: [{ id: 'n1', toUserId: 'u1' }]
  }));
  fs.writeFileSync(path.join(source, 'messages', 'c1.jsonl'),
    '{"id":"msg1","seq":1}\n');
  const routePlan = buildRoutePlan({
    users,
    chats,
    shardCount: 7,
    ports: [7080, 7180, 7280, 7380, 7480, 7580, 7680],
    topologyId: 'server-b-mainline-shards-7',
    baselineDate: '2026-11-16',
    createdAt: '2026-11-16T00:00:00Z'
  });
  const report = rehearseShardPlacement({
    sourceDir: source,
    stageDir: stage,
    rehydrateDir: rehydrate,
    routePlan,
    threadLimit: 10
  });
  assert.strictEqual(report.ok, true, JSON.stringify(report.failures));
  assert.deepStrictEqual(report.failures, []);
  assert.strictEqual(report.counts.users, 2);
  assert.strictEqual(report.counts.messageThreads, 1);
  assert.ok(fs.existsSync(path.join(rehydrate, 'messages', 'c1.jsonl')));
  console.log('shard-placement-rehearsal: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
