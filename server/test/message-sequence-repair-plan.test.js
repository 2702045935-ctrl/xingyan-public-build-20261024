'use strict';

const assert = require('assert');
const { spawnSync } = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-sequence-repair-'));
const dataDir = path.join(root, 'data');
const messagesDir = path.join(dataDir, 'messages');
const secretFile = path.join(dataDir, 'secret.key');
const inventoryFile = path.join(root, 'inventory.json');
const out = path.join(root, 'repair.json');
fs.mkdirSync(messagesDir, { recursive: true });

try {
  fs.writeFileSync(secretFile, 'repair-secret', 'utf8');
  const makeLine = (chatId, message) => {
    const key = crypto.createHmac('sha256', 'repair-secret').update('msg:' + chatId).digest();
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
    const ciphertext = Buffer.concat([
      cipher.update(JSON.stringify(message), 'utf8'),
      cipher.final()
    ]);
    return JSON.stringify({
      e: 1,
      iv: iv.toString('base64'),
      tag: cipher.getAuthTag().toString('base64'),
      ct: ciphertext.toString('base64')
    });
  };
  fs.writeFileSync(path.join(messagesDir, 'c1.jsonl'), [
    { id: 'm2', seq: 1, createdAt: '2026-11-16T00:00:02Z' },
    { id: 'm1', seq: 1, createdAt: '2026-11-16T00:00:01Z' }
  ].map((message) => makeLine('c1', message)).join('\n') + '\n');
  fs.writeFileSync(path.join(messagesDir, 'c2.jsonl'), [
    { id: 'm3', seq: 1, createdAt: '2026-11-16T00:00:03Z' },
    { id: 'm4', seq: 3, createdAt: '2026-11-16T00:00:04Z' }
  ].map((message) => makeLine('c2', message)).join('\n') + '\n');
  fs.writeFileSync(path.join(dataDir, 'reads.json'), JSON.stringify({
    reads: { u1: { c1: 1 } }
  }));
  fs.writeFileSync(path.join(dataDir, 'delivered.json'), JSON.stringify({
    delivered: { u1: { c1: 1 } }
  }));
  fs.writeFileSync(path.join(dataDir, 'chats.json'), JSON.stringify({
    chats: [{ id: 'c1', seq: 1 }, { id: 'c2', seq: 3 }]
  }));
  fs.writeFileSync(inventoryFile, JSON.stringify({
    errors: [
      { kind: 'message-seq-duplicate', id: 'c1:1' },
      { kind: 'message-seq-gap', id: 'c2:2' }
    ]
  }));
  const result = spawnSync(process.execPath, [
    path.join(__dirname, '..', 'tools', 'message-sequence-repair-plan.js'),
    '--data', dataDir,
    '--secret', secretFile,
    '--inventory', inventoryFile,
    '--out', out
  ], { encoding: 'utf8' });
  assert.strictEqual(result.status, 0, result.stderr || result.stdout);
  const report = JSON.parse(fs.readFileSync(out, 'utf8'));
  assert.strictEqual(report.ok, true);
  assert.strictEqual(report.plannedChats, 2);
  assert.strictEqual(report.changedMessages, 2);
  assert.strictEqual(report.changedReadCursors, 1);
  assert.strictEqual(report.plans[0].rows[0].id, 'm1');
  assert.strictEqual(report.plans[0].rows[0].newSeq, 1);
  assert.strictEqual(report.plans[0].rows[1].newSeq, 2);
  console.log('message-sequence-repair-plan: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
