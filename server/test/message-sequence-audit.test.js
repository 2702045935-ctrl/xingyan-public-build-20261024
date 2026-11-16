'use strict';

const assert = require('assert');
const { spawnSync } = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-message-sequence-'));
const dataDir = path.join(root, 'data');
const messagesDir = path.join(dataDir, 'messages');
const secretFile = path.join(dataDir, 'secret.key');
const out = path.join(root, 'report.json');
fs.mkdirSync(messagesDir, { recursive: true });

try {
  fs.writeFileSync(secretFile, 'test-message-secret', 'utf8');
  const key = crypto.createHmac('sha256', 'test-message-secret').update('msg:c1').digest();
  const makeLine = (message) => {
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
  const rows = [
    { id: 'm1', seq: 1, senderId: 'u1', kind: 'text', content: 'a', createdAt: '1' },
    { id: 'm1', seq: 1, senderId: 'u1', kind: 'text', content: 'a', createdAt: '1' },
    { id: 'm3', seq: 2, senderId: 'u2', kind: 'text', content: 'c', createdAt: '2' },
    { id: 'm4', seq: 2, senderId: 'u2', kind: 'text', content: 'd', createdAt: '3' }
  ];
  fs.writeFileSync(path.join(messagesDir, 'c1.jsonl'),
    rows.map(makeLine).join('\n') + '\n');
  const result = spawnSync(process.execPath, [
    path.join(__dirname, '..', 'tools', 'message-sequence-audit.js'),
    '--data', dataDir,
    '--secret', secretFile,
    '--out', out
  ], { encoding: 'utf8' });
  assert.strictEqual(result.status, 2, result.stderr || result.stdout);
  const report = JSON.parse(fs.readFileSync(out, 'utf8'));
  assert.strictEqual(report.ok, false);
  assert.strictEqual(report.classes['same-id'], 1);
  assert.strictEqual(report.classes['different-content'], 1);
  console.log('message-sequence-audit: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
