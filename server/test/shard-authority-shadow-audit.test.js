'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');
const { ShardAuthorityStore } = require('../lib/shard-authority-store');
const {
  loadShardSnapshot,
  importShardSnapshot
} = require('../lib/shard-authority-migration');
const { auditShardAuthority } = require('../lib/shard-authority-shadow-audit');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-authority-shadow-'));
const dataDir = path.join(root, 'data');
const messagesDir = path.join(dataDir, 'messages');
const databaseFile = path.join(root, 'authority.sqlite3');
fs.mkdirSync(messagesDir, { recursive: true });

try {
  fs.writeFileSync(path.join(dataDir, 'secret.key'), 'shadow-secret', 'utf8');
  fs.writeFileSync(path.join(dataDir, 'chats.json'), JSON.stringify({
    chats: [{ id: 'direct-shadow', type: 'direct', title: 'Shadow', memberIds: ['u1', 'u2'] }]
  }), 'utf8');
  fs.writeFileSync(path.join(messagesDir, 'direct-shadow.jsonl'), [
    { id: 'm1', chatId: 'direct-shadow', senderId: 'u1', seq: 1, content: 'one',
      createdAt: '2026-11-17T00:00:01.000Z' },
    { id: 'm2', chatId: 'direct-shadow', senderId: 'u2', seq: 2, content: 'two',
      createdAt: '2026-11-17T00:00:02.000Z' }
  ].map(JSON.stringify).join('\n') + '\n', 'utf8');
  const snapshot = loadShardSnapshot({
    dataDir,
    secretFile: path.join(dataDir, 'secret.key'),
    directOnly: true
  });
  const store = new ShardAuthorityStore({
    shardId: 1,
    topologyId: 'shadow-shards-7',
    databaseFile,
    writerEpoch: 1
  });
  importShardSnapshot(store, snapshot);
  store.checkpoint();
  store.close();

  let report = auditShardAuthority({ databaseFile, snapshot });
  assert.strictEqual(report.ok, true);
  assert.strictEqual(report.chats, 1);
  assert.strictEqual(report.messages, 2);

  const db = new DatabaseSync(databaseFile);
  const row = db.prepare(
    'SELECT payload_json FROM reliable_messages WHERE message_id = ?'
  ).get('m2');
  const payload = JSON.parse(row.payload_json);
  payload.content = 'tampered';
  db.prepare(
    'UPDATE reliable_messages SET payload_json = ? WHERE message_id = ?'
  ).run(JSON.stringify(payload), 'm2');
  db.close();

  report = auditShardAuthority({ databaseFile, snapshot });
  assert.strictEqual(report.ok, false);
  assert.ok(report.issues.some((issue) => issue.code === 'message-content'));
  console.log('shard-authority-shadow-audit: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
