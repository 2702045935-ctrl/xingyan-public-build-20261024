'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');
const { auditMessageConsistency } = require('../lib/message-consistency-audit');
const { MessageReliabilityStore } = require('../lib/message-reliability');
const { createSecurityVault } = require('../lib/security-vault');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-message-audit-'));

function digestTree(directory) {
  const rows = [];
  const walk = (current, prefix) => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })
      .sort((left, right) => left.name.localeCompare(right.name))) {
      const full = path.join(current, entry.name);
      const relative = prefix ? prefix + '/' + entry.name : entry.name;
      if (entry.isDirectory()) walk(full, relative);
      else {
        rows.push({
          path: relative,
          sha256: crypto.createHash('sha256').update(fs.readFileSync(full)).digest('hex')
        });
      }
    }
  };
  walk(directory, '');
  return rows;
}

function message(id, chatId, seq, senderId, clientId, content) {
  return {
    id,
    chatId,
    seq,
    senderId,
    clientId,
    kind: 'text',
    content,
    createdAt: `2026-11-15T00:00:0${seq}.000Z`
  };
}

async function cleanFixture() {
  const dataDir = path.join(root, 'clean');
  fs.mkdirSync(path.join(dataDir, 'messages'), { recursive: true });
  const secret = 'message-audit-secret';
  fs.writeFileSync(path.join(dataDir, 'secret.key'), secret);
  const vault = createSecurityVault({ dataDir, rootMaterial: secret });
  vault.rotate('message', 'audit-test', 'exercise encrypted message versions');

  const c1 = [
    message('c1-m1', 'c1', 1, 'u1', 'client-c1-1', 'first'),
    message('c1-m2', 'c1', 2, 'u2', 'client-c1-2', 'second')
  ];
  const c2 = [
    message('c2-m1', 'c2', 1, 'u1', 'client-c2-1', 'encrypted')
  ];
  fs.writeFileSync(path.join(dataDir, 'messages', 'c1.jsonl'),
    c1.map((row) => JSON.stringify(row)).join('\n') + '\n');
  fs.writeFileSync(path.join(dataDir, 'messages', 'c2.jsonl'),
    JSON.stringify(vault.sealJson('message', 'c2', c2[0])) + '\n');

  const store = new MessageReliabilityStore({
    databaseFile: path.join(dataDir, 'message-reliability.sqlite3'),
    now: () => '2026-11-15T00:00:00.000Z',
    uid: (() => {
      let index = 0;
      return (prefix) => `${prefix}_${++index}`;
    })()
  });
  assert.deepStrictEqual(store.importMessages('c1', c1), {
    imported: 2,
    existing: 0,
    conflicts: 0,
    total: 2
  });
  assert.deepStrictEqual(store.importMessages('c2', c2), {
    imported: 1,
    existing: 0,
    conflicts: 0,
    total: 1
  });
  store.setMetadata('legacy-backfill-v1', JSON.stringify({
    chats: 2,
    total: 3,
    imported: 3,
    existing: 0,
    conflicts: 0
  }));
  store.close();

  const before = digestTree(dataDir);
  const first = await auditMessageConsistency({
    dataDir,
    secret,
    sourceId: 'clean-fixture'
  });
  const second = await auditMessageConsistency({
    dataDir,
    secret,
    sourceId: 'clean-fixture'
  });
  const after = digestTree(dataDir);

  assert.strictEqual(first.ok, true, JSON.stringify(first.issues, null, 2));
  assert.strictEqual(first.readOnly, true);
  assert.strictEqual(first.counts.messageFiles, 2);
  assert.strictEqual(first.counts.messages, 3);
  assert.strictEqual(first.counts.reliabilityMessages, 3);
  assert.strictEqual(first.errorCount, 0);
  assert.strictEqual(first.warningCount, 0);
  assert.deepStrictEqual(after, before, 'audit must not mutate source data');
  assert.strictEqual(first.fingerprint, second.fingerprint,
    'identical source data must produce a stable fingerprint');
}

async function invalidFixture() {
  const dataDir = path.join(root, 'invalid');
  fs.mkdirSync(path.join(dataDir, 'messages'), { recursive: true });
  const databaseFile = path.join(dataDir, 'message-reliability.sqlite3');
  const store = new MessageReliabilityStore({
    databaseFile,
    now: () => '2026-11-15T00:00:00.000Z',
    uid: (() => {
      let index = 0;
      return (prefix) => `${prefix}_${++index}`;
    })()
  });
  store.reserveMessage(message('m1', 'c1', 1, 'u1', 'client-1', 'first'));
  store.reserveMessage(message('m2', 'c1', 2, 'u2', 'client-2', 'second'));
  store.reserveMessage(message('m3', 'c1', 3, 'u1', 'client-3', 'third'));
  store.reserveMessage(message('other', 'c2', 1, 'u1', 'client-4', 'other'));
  store.close();

  const validM1 = message('m1', 'c1', 1, 'u1', 'client-1', 'first');
  const duplicateClient = message('m3', 'c1', 3, 'u1', 'client-1', 'third');
  const crossChat = message('m1', 'c2', 2, 'u1', 'client-5', 'cross');
  const extra = message('m4', 'c1', 4, 'u2', 'client-6', 'extra');
  fs.writeFileSync(path.join(dataDir, 'messages', 'c1.jsonl'), [
    JSON.stringify(validM1),
    '{not-json',
    JSON.stringify(duplicateClient),
    JSON.stringify(extra),
    JSON.stringify(message('missing-sequence', 'c1', 0, 'u1', '', 'invalid'))
  ].join('\n') + '\n');
  fs.writeFileSync(path.join(dataDir, 'messages', 'c2.jsonl'),
    JSON.stringify(crossChat) + '\n'
      + JSON.stringify({ e: 1, iv: 'bad', tag: 'bad', ct: 'bad' }) + '\n');

  const db = new DatabaseSync(databaseFile);
  db.prepare('UPDATE chat_sequence SET last_seq = 9 WHERE chat_id = ?').run('c1');
  db.prepare('UPDATE reliable_messages SET payload_json = ? WHERE message_id = ?')
    .run(JSON.stringify(Object.assign({}, message('m2', 'c1', 2, 'u2', 'client-2', 'changed'))),
      'm2');
  db.close();

  const report = await auditMessageConsistency({
    dataDir,
    sourceId: 'invalid-fixture',
    requireClientId: true
  });

  assert.strictEqual(report.ok, false);
  for (const kind of [
    'message-invalid-json',
    'message-invalid-envelope',
    'message-id-cross-chat',
    'message-seq-gap',
    'client-id-duplicate',
    'client-id-missing',
    'reliability-message-missing',
    'message-file-row-missing',
    'reliability-message-payload-mismatch',
    'last-seq-file-mismatch'
  ]) {
    assert.ok(report.issueCounts[kind] > 0, 'missing expected issue ' + kind);
  }
  assert.ok(report.issues.every((row, index) => {
    if (index === 0) return true;
    return JSON.stringify(report.issues[index - 1]) <= JSON.stringify(row);
  }), 'issues must be deterministically sorted');
}

async function preReliabilityFixture() {
  const dataDir = path.join(root, 'pre-reliability');
  fs.mkdirSync(path.join(dataDir, 'messages'), { recursive: true });
  const rows = [
    message('pre-m1', 'pre-c1', 1, 'u1', 'pre-client-1', 'one'),
    message('pre-m2', 'pre-c1', 2, 'u2', 'pre-client-2', 'two')
  ];
  fs.writeFileSync(path.join(dataDir, 'messages', 'pre-c1.jsonl'),
    rows.map((row) => JSON.stringify(row)).join('\n') + '\n');

  const report = await auditMessageConsistency({
    dataDir,
    sourceId: 'pre-reliability-fixture'
  });
  assert.strictEqual(report.ok, true, JSON.stringify(report.issues, null, 2));
  assert.strictEqual(report.reliability.present, false);
  assert.strictEqual(report.counts.messages, 2);
  assert.strictEqual(fs.existsSync(path.join(dataDir, 'message-reliability.sqlite3')), false);
}

async function activeWalFixture() {
  const dataDir = path.join(root, 'active-wal');
  fs.mkdirSync(path.join(dataDir, 'messages'), { recursive: true });
  const databaseFile = path.join(dataDir, 'message-reliability.sqlite3');
  const store = new MessageReliabilityStore({
    databaseFile,
    now: () => '2026-11-15T00:00:00.000Z',
    uid: (() => {
      let index = 0;
      return (prefix) => `${prefix}_${++index}`;
    })()
  });
  const stored = store.reserveMessage(
    message('wal-m1', 'wal-c1', 1, 'u1', 'wal-client-1', 'active wal')
  ).message;
  fs.writeFileSync(path.join(dataDir, 'messages', 'wal-c1.jsonl'),
    JSON.stringify(stored) + '\n');

  const before = digestTree(dataDir);
  const report = await auditMessageConsistency({
    dataDir,
    sourceId: 'active-wal-fixture'
  });
  const after = digestTree(dataDir);
  store.close();

  assert.strictEqual(report.ok, false);
  assert.ok(report.issueCounts['reliability-database-not-checkpointed'] > 0);
  assert.deepStrictEqual(after, before, 'active-WAL audit must not touch source files');
}

async function main() {
  await cleanFixture();
  await invalidFixture();
  await preReliabilityFixture();
  await activeWalFixture();
  console.log('message-consistency-audit: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
}).finally(() => {
  fs.rmSync(root, { recursive: true, force: true });
});
