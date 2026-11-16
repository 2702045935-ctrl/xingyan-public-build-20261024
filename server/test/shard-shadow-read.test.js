'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { buildRoutePlan } = require('../lib/shard-route-plan');
const { ownerFor } = require('../lib/shard-placement-plan');
const { rehearseShardPlacement } = require('../lib/shard-placement-rehearsal');
const {
  PhysicalShardReader,
  LegacyDataReader,
  runShadowReadAudit
} = require('../lib/shard-shadow-read');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-shadow-read-'));
const source = path.join(root, 'source');
const physical = path.join(root, 'physical');
const rehydrate = path.join(root, 'rehydrate');
fs.mkdirSync(path.join(source, 'messages'), { recursive: true });

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(value));
}

try {
  const users = [{ id: 'u1', nickname: 'A' }, { id: 'u2', nickname: 'B' }];
  const chats = [{ id: 'c1', memberIds: ['u1', 'u2'] }, { id: 'c2', memberIds: ['u1', 'u2'] }];
  const moments = [{ id: 'm1', authorId: 'u1' }, { id: 'm2', authorId: 'u2' }];
  writeJson(path.join(source, 'users.json'), { users });
  writeJson(path.join(source, 'friendships.json'), {
    friendships: [{ id: 'f1', fromId: 'u1', toId: 'u2' }]
  });
  writeJson(path.join(source, 'chats.json'), { chats });
  writeJson(path.join(source, 'reads.json'), { reads: { u1: { c1: 2 }, u2: { c2: 1 } } });
  writeJson(path.join(source, 'friendmeta.json'), {
    byOwner: { u1: { u2: { remark: 'B' } } }
  });
  writeJson(path.join(source, 'moments.json'), { moments });
  writeJson(path.join(source, 'moment-notices.json'), {
    items: [{ id: 'n1', toUserId: 'u1' }]
  });
  fs.writeFileSync(path.join(source, 'messages', 'c1.jsonl'), '{"id":"m1","seq":1}\n');
  fs.writeFileSync(path.join(source, 'messages', 'c2.jsonl'),
    '{"id":"m2","seq":1}\n{"id":"m3","seq":2}\n');

  const routePlan = buildRoutePlan({
    users,
    chats,
    shardCount: 7,
    ports: [7080, 7180, 7280, 7380, 7480, 7580, 7680],
    topologyId: 'server-b-mainline-shards-7',
    baselineDate: '2026-11-16',
    createdAt: '2026-11-16T00:00:00Z'
  });
  const rehearsal = rehearseShardPlacement({
    sourceDir: source,
    stageDir: physical,
    rehydrateDir: rehydrate,
    routePlan
  });
  assert.strictEqual(rehearsal.ok, true, JSON.stringify(rehearsal.failures));

  const legacy = new LegacyDataReader(source);
  const shadow = new PhysicalShardReader({ root: physical, routePlan });
  assert.deepStrictEqual(shadow.readUser('u1'), legacy.readUser('u1'));
  assert.deepStrictEqual(shadow.readChat('c2'), legacy.readChat('c2'));
  assert.deepStrictEqual(shadow.readMessages('c1'), legacy.readMessages('c1'));
  assert.strictEqual(shadow.readReadCursor('u1', 'c1'), 2);
  assert.deepStrictEqual(shadow.readFriendMeta('u1', 'u2'), { remark: 'B' });

  let report = runShadowReadAudit({
    sourceDir: source,
    physicalRoot: physical,
    routePlan
  });
  assert.strictEqual(report.ok, true, JSON.stringify(report.diffs));
  assert.strictEqual(report.readOnly, true);
  assert.strictEqual(report.checked.users, 2);
  assert.strictEqual(report.checked.chats, 2);
  assert.strictEqual(report.checked.messages, 2);
  assert.match(report.fingerprint, /^[a-f0-9]{64}$/);

  const chatShard = shadow.owner('chat', 'c1');
  const chatFile = path.join(physical, 'shards', String(chatShard), 'chats.json');
  const chatData = JSON.parse(fs.readFileSync(chatFile, 'utf8'));
  chatData.chats[0].title = 'tampered';
  writeJson(chatFile, chatData);
  shadow.cache.clear();
  report = runShadowReadAudit({ sourceDir: source, physicalRoot: physical, routePlan });
  assert.strictEqual(report.ok, false);
  assert.ok(report.diffs.some((row) => row.kind === 'chat' && row.id === 'c1'));

  const extraShard = ownerFor(routePlan, 7, 'user', 'u_extra');
  const usersFile = path.join(physical, 'shards', String(extraShard), 'users.json');
  const usersData = JSON.parse(fs.readFileSync(usersFile, 'utf8'));
  usersData.users.push({ id: 'u_extra' });
  writeJson(usersFile, usersData);
  report = runShadowReadAudit({ sourceDir: source, physicalRoot: physical, routePlan });
  assert.strictEqual(report.ok, false);
  assert.ok(report.diffs.some((row) => row.kind === 'user-extra' && row.id === 'u_extra'));

  console.log('shard-shadow-read: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
