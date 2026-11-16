'use strict';

const assert = require('assert');
const { spawnSync } = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-upload-repair-'));
const dataDir = path.join(root, 'data');
const messagesDir = path.join(dataDir, 'messages');
const oldDir = path.join(root, 'old-uploads');
const secretFile = path.join(dataDir, 'secret.key');
const inventoryFile = path.join(root, 'inventory.json');
const out = path.join(root, 'plan.json');
fs.mkdirSync(messagesDir, { recursive: true });
fs.mkdirSync(oldDir, { recursive: true });

try {
  fs.writeFileSync(secretFile, 'upload-secret', 'utf8');
  fs.writeFileSync(path.join(oldDir, 'found.png'), 'image');
  const key = crypto.createHmac('sha256', 'upload-secret').update('msg:c1').digest();
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const message = {
    id: 'm1',
    seq: 1,
    senderId: 'u1',
    kind: 'image',
    content: '/uploads/found.png',
    createdAt: '2026-11-16T00:00:00Z'
  };
  const ciphertext = Buffer.concat([
    cipher.update(JSON.stringify(message), 'utf8'),
    cipher.final()
  ]);
  fs.writeFileSync(path.join(messagesDir, 'c1.jsonl'), JSON.stringify({
    e: 1,
    iv: iv.toString('base64'),
    tag: cipher.getAuthTag().toString('base64'),
    ct: ciphertext.toString('base64')
  }) + '\n');
  fs.writeFileSync(inventoryFile, JSON.stringify({
    errors: [{ kind: 'upload-missing', id: 'found.png' }]
  }));
  const result = spawnSync(process.execPath, [
    path.join(__dirname, '..', 'tools', 'upload-reference-repair-plan.js'),
    '--data', dataDir,
    '--secret', secretFile,
    '--inventory', inventoryFile,
    '--out', out,
    '--search-root', oldDir
  ], { encoding: 'utf8' });
  assert.strictEqual(result.status, 0, result.stderr || result.stdout);
  const plan = JSON.parse(fs.readFileSync(out, 'utf8'));
  assert.strictEqual(plan.missing, 1);
  assert.strictEqual(plan.recoverable, 1);
  assert.strictEqual(plan.unresolvedReferences, 0);
  assert.strictEqual(plan.items[0].sourceFiles.length, 1);
  console.log('upload-reference-repair-plan: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
