'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { buildRoutePlan } = require('../lib/shard-route-plan');
const { ownerFor } = require('../lib/shard-placement-plan');
const { verifyPhysicalLayout, REQUIRED_FILES } = require('../lib/shard-physical-layout');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-physical-layout-'));
const physical = path.join(root, 'physical');
const users = [{ id: 'u1' }, { id: 'u2' }, { id: 'u3' }];
const chats = [{ id: 'c1' }, { id: 'c2' }, { id: 'c3' }];
const moments = [{ id: 'm1' }, { id: 'm2' }, { id: 'm3' }];
const routePlan = buildRoutePlan({
  users,
  chats,
  shardCount: 7,
  ports: [7080, 7180, 7280, 7380, 7480, 7580, 7680],
  topologyId: 'server-b-mainline-shards-7',
  baselineDate: '2026-11-16',
  createdAt: '2026-11-16T00:00:00Z'
});

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(value));
}

function stage() {
  for (let shard = 0; shard < 7; shard += 1) {
    const dir = path.join(physical, 'shards', String(shard));
    fs.mkdirSync(path.join(dir, 'messages'), { recursive: true });
    writeJson(path.join(dir, 'users.json'), {
      users: users.filter((row) => ownerFor(routePlan, 7, 'user', row.id) === shard)
    });
    writeJson(path.join(dir, 'friendships.json'), { friendships: [] });
    writeJson(path.join(dir, 'chats.json'), {
      chats: chats.filter((row) => ownerFor(routePlan, 7, 'chat', row.id) === shard)
    });
    writeJson(path.join(dir, 'reads.json'), { reads: {} });
    writeJson(path.join(dir, 'friendmeta.json'), { byOwner: {} });
    writeJson(path.join(dir, 'moments.json'), {
      moments: moments.filter((row) => ownerFor(routePlan, 7, 'moment', row.id) === shard)
    });
    writeJson(path.join(dir, 'moment-notices.json'), { items: [] });
  }
  for (const chat of chats) {
    const owner = ownerFor(routePlan, 7, 'chat', chat.id);
    fs.writeFileSync(path.join(physical, 'shards', String(owner), 'messages',
      chat.id + '.jsonl'), '{"id":"' + chat.id + '-m1","seq":1}\n');
  }
}

try {
  stage();
  const report = verifyPhysicalLayout({ root: physical, routePlan });
  assert.strictEqual(report.ok, true, JSON.stringify(report.failures));
  assert.strictEqual(report.counts.users, 3);
  assert.strictEqual(report.counts.chats, 3);
  assert.strictEqual(report.counts.messages, 3);
  assert.match(report.hash, /^[a-f0-9]{64}$/);

  const wrongShard = ownerFor(routePlan, 7, 'user', 'u1') === 0 ? 1 : 0;
  const usersFile = path.join(physical, 'shards', String(wrongShard), 'users.json');
  const data = JSON.parse(fs.readFileSync(usersFile, 'utf8'));
  data.users.push({ id: 'u1', duplicate: true });
  writeJson(usersFile, data);
  let tampered = verifyPhysicalLayout({ root: physical, routePlan });
  assert.strictEqual(tampered.ok, false);
  assert.ok(tampered.failures.some((row) => row.code === 'duplicate-authority'));

  writeJson(path.join(physical, 'users.json'), { users });
  tampered = verifyPhysicalLayout({ root: physical, routePlan });
  assert.ok(tampered.failures.some((row) => row.code === 'shared-root-entry'));
  fs.unlinkSync(path.join(physical, 'users.json'));

  const expectedReadShard = ownerFor(routePlan, 7, 'snapshot_reads', 'c1|u1');
  const wrongReadShard = (expectedReadShard + 1) % 7;
  const readsFile = path.join(physical, 'shards', String(wrongReadShard), 'reads.json');
  const reads = JSON.parse(fs.readFileSync(readsFile, 'utf8'));
  reads.reads.u1 = { c1: 1 };
  writeJson(readsFile, reads);
  tampered = verifyPhysicalLayout({ root: physical, routePlan });
  assert.ok(tampered.failures.some((row) =>
    row.code === 'authority-wrong-owner' && row.kind === 'snapshot_reads'
  ));

  const wrongChat = chats[0].id;
  const expectedChatShard = ownerFor(routePlan, 7, 'chat', wrongChat);
  const wrongMessageShard = (expectedChatShard + 1) % 7;
  fs.writeFileSync(path.join(physical, 'shards', String(wrongMessageShard), 'messages',
    wrongChat + '.jsonl'), '{"bad":true}\n');
  tampered = verifyPhysicalLayout({ root: physical, routePlan });
  assert.ok(tampered.failures.some((row) => row.code === 'message-wrong-owner'));

  fs.writeFileSync(path.join(physical, 'shards', '0', 'uploads.jpg'), 'x');
  tampered = verifyPhysicalLayout({ root: physical, routePlan });
  assert.ok(tampered.failures.some((row) => row.code === 'unexpected-shard-entry'));

  assert.strictEqual(REQUIRED_FILES.length, 7);
  console.log('shard-physical-layout: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
