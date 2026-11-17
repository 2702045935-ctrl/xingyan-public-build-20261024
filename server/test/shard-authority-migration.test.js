'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { ShardAuthorityStore } = require('../lib/shard-authority-store');
const {
  loadShardSnapshot,
  importShardSnapshot
} = require('../lib/shard-authority-migration');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-authority-migration-'));
const dataDir = path.join(root, 'data');
const messagesDir = path.join(dataDir, 'messages');
fs.mkdirSync(messagesDir, { recursive: true });

try {
  fs.writeFileSync(path.join(dataDir, 'secret.key'), 'migration-secret', 'utf8');
  fs.writeFileSync(path.join(dataDir, 'chats.json'), JSON.stringify({
    chats: [
      { id: 'direct-1', type: 'direct', title: 'Direct', memberIds: ['u1', 'u2'] },
      { id: 'group-1', type: 'group', title: 'Group', memberIds: ['u1', 'u2', 'u3'] }
    ]
  }), 'utf8');
  fs.writeFileSync(path.join(messagesDir, 'direct-1.jsonl'), [
    { id: 'm2', chatId: 'direct-1', senderId: 'u2', seq: 9, content: 'two',
      createdAt: '2026-11-17T00:00:02.000Z' },
    { id: 'm1', chatId: 'direct-1', senderId: 'u1', seq: 4, content: 'one',
      createdAt: '2026-11-17T00:00:01.000Z' }
  ].map(JSON.stringify).join('\n') + '\n', 'utf8');
  fs.writeFileSync(path.join(messagesDir, 'group-1.jsonl'), JSON.stringify({
    id: 'g1',
    chatId: 'group-1',
    senderId: 'u1',
    seq: 1,
    content: 'group'
  }) + '\n', 'utf8');

  const snapshot = loadShardSnapshot({
    dataDir,
    secretFile: path.join(dataDir, 'secret.key'),
    directOnly: true
  });
  assert.strictEqual(snapshot.chats, 1);
  assert.strictEqual(snapshot.messages, 2);
  assert.deepStrictEqual(snapshot.snapshots[0].messages.map((row) => row.seq), [1, 2]);
  assert.deepStrictEqual(snapshot.snapshots[0].messages.map((row) => row.id), ['m1', 'm2']);

  const store = new ShardAuthorityStore({
    shardId: 3,
    topologyId: 'migration-shards-7',
    databaseFile: path.join(root, 'authority.sqlite3'),
    writerEpoch: 1
  });
  const report = importShardSnapshot(store, snapshot);
  assert.strictEqual(report.ok, true);
  assert.strictEqual(report.messages, 2);
  assert.strictEqual(store.readChat('direct-1').seq, 2);
  assert.strictEqual(store.readChat('group-1'), null);
  assert.strictEqual(store.verify().ok, true);
  store.close();
  console.log('shard-authority-migration: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
