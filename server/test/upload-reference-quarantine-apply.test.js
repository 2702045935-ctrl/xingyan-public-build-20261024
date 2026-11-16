'use strict';

const assert = require('assert');
const { spawnSync } = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { openMessage } = require('../lib/shard-data-inventory');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-upload-quarantine-'));
const source = path.join(root, 'source');
const target = path.join(root, 'target');
const plan = path.join(root, 'plan.json');
const report = path.join(root, 'report.json');
const secretFile = path.join(source, 'secret.key');
fs.mkdirSync(path.join(source, 'messages'), { recursive: true });

try {
  fs.writeFileSync(secretFile, 'quarantine-secret', 'utf8');
  const key = crypto.createHmac('sha256', 'quarantine-secret').update('msg:c1').digest();
  const seal = (message) => {
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
  fs.writeFileSync(path.join(source, 'messages', 'c1.jsonl'), [
    { id: 'm1', seq: 1, kind: 'image', content: '/uploads/missing.png' },
    { id: 'm2', seq: 2, kind: 'music', content: '{"url":"/uploads/x.mp3"}' }
  ].map(seal).join('\n') + '\n');
  fs.writeFileSync(plan, JSON.stringify({
    planHash: 'a'.repeat(64),
    items: [
      { action: 'quarantine', references: [{ chatId: 'c1', messageId: 'm1', path: '/uploads/missing.png' }] },
      { action: 'quarantine', references: [{ chatId: 'c1', messageId: 'm2', path: '/uploads/x.mp3' }] }
    ]
  }));
  const result = spawnSync(process.execPath, [
    path.join(__dirname, '..', 'tools', 'upload-reference-quarantine-apply.js'),
    '--source', source,
    '--target', target,
    '--secret', secretFile,
    '--plan', plan,
    '--out', report
  ], { encoding: 'utf8' });
  assert.strictEqual(result.status, 0, result.stderr || result.stdout);
  const rows = fs.readFileSync(path.join(target, 'messages', 'c1.jsonl'), 'utf8')
    .split('\n').filter(Boolean).map((line) => openMessage('quarantine-secret', 'c1', line, null));
  assert.strictEqual(rows[0].kind, 'text');
  assert.strictEqual(rows[0].content, '[媒体内容已丢失]');
  assert.strictEqual(rows[0].unavailableMedia.path, '/uploads/missing.png');
  assert.strictEqual(rows[1].kind, 'music');
  assert.strictEqual(rows[1].recoveryPending, true);
  const summary = JSON.parse(fs.readFileSync(report, 'utf8'));
  assert.strictEqual(summary.quarantineMessages, 1);
  assert.strictEqual(summary.recoveryPendingMessages, 1);
  console.log('upload-reference-quarantine-apply: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
