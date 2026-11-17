'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { createSecurityVault } = require('../lib/security-vault');
const { migrateDataDir } = require('../../deploy/dual-cell/migrate-key-domain');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-key-domain-'));

function writeJson(file, value) {
  fs.writeFileSync(file, JSON.stringify(value), 'utf8');
}

try {
  const dataDir = path.join(root, 'data');
  const messagesDir = path.join(dataDir, 'messages');
  fs.mkdirSync(messagesDir, { recursive: true });
  fs.writeFileSync(path.join(dataDir, 'current-secret.key'), 'current-domain', 'utf8');
  fs.writeFileSync(path.join(dataDir, 'target-secret.key'), 'target-domain', 'utf8');

  const current = createSecurityVault({
    dataDir: path.join(root, 'current-ring'),
    rootMaterial: 'current-domain'
  });
  const target = createSecurityVault({
    dataDir: path.join(root, 'target-ring'),
    rootMaterial: 'target-domain'
  });
  current.ensure();
  target.ensure();
  writeJson(path.join(dataDir, 'current-keyring.json'), current.keyring);
  writeJson(path.join(dataDir, 'target-keyring.json'), target.keyring);

  const chatId = 'chat-key-domain';
  const already = target.sealJson('message', chatId, { id: 'target', seq: 1 });
  const migrate = current.sealJson('message', chatId, { id: 'current', seq: 2 });
  fs.writeFileSync(path.join(messagesDir, chatId + '.jsonl'),
    JSON.stringify(already) + '\n' + JSON.stringify(migrate) + '\n', 'utf8');

  const report = migrateDataDir({
    dataDir,
    currentSecret: path.join(dataDir, 'current-secret.key'),
    currentKeyring: path.join(dataDir, 'current-keyring.json'),
    targetSecret: path.join(dataDir, 'target-secret.key'),
    targetKeyring: path.join(dataDir, 'target-keyring.json'),
    backupDir: path.join(root, 'backup')
  });
  assert.strictEqual(report.encryptedMessages, 2);
  assert.strictEqual(report.alreadyTarget, 1);
  assert.strictEqual(report.migrated, 1);
  assert.deepStrictEqual(report.changedFiles, [chatId + '.jsonl']);

  const rows = fs.readFileSync(path.join(messagesDir, chatId + '.jsonl'), 'utf8')
    .split(/\r?\n/).filter(Boolean).map(JSON.parse);
  assert.deepStrictEqual(target.openJson('message', chatId, rows[0], null), { id: 'target', seq: 1 });
  assert.deepStrictEqual(target.openJson('message', chatId, rows[1], null), { id: 'current', seq: 2 });
  assert.ok(fs.existsSync(path.join(root, 'backup', chatId + '.jsonl')));
  console.log('dual-cell-key-domain: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
