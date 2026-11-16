'use strict';

const assert = require('assert');
const { spawnSync } = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { SecurityVault } = require('../lib/security-vault');
const { openMessage } = require('../lib/shard-data-inventory');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-sequence-apply-'));
const source = path.join(root, 'source');
const target = path.join(root, 'target');
const plan = path.join(root, 'plan.json');
const report = path.join(root, 'report.json');
const secretFile = path.join(source, 'secret.key');
fs.mkdirSync(path.join(source, 'messages'), { recursive: true });

try {
  fs.writeFileSync(secretFile, 'apply-secret', 'utf8');
  const key = crypto.createHmac('sha256', 'apply-secret').update('msg:c1').digest();
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
    { id: 'm2', seq: 1, createdAt: '2' },
    { id: 'm1', seq: 1, createdAt: '1' }
  ].map(seal).join('\n') + '\n');
  fs.writeFileSync(path.join(source, 'chats.json'), JSON.stringify({
    chats: [{ id: 'c1', seq: 1 }]
  }));
  fs.writeFileSync(path.join(source, 'reads.json'), JSON.stringify({
    reads: { u1: { c1: 1 } }, cleared: {}
  }));
  fs.writeFileSync(path.join(source, 'delivered.json'), JSON.stringify({
    delivered: { u1: { c1: 1 } }
  }));
  fs.writeFileSync(plan, JSON.stringify({
    ok: true,
    plannedChats: 1,
    changedReadCursors: 1,
    changedDeliveredCursors: 1,
    planHash: 'a'.repeat(64),
    plans: [{
      chatId: 'c1',
      newChatSeq: 2,
      rows: [
        { id: 'm1', oldSeq: 1, newSeq: 1, createdAt: '1' },
        { id: 'm2', oldSeq: 1, newSeq: 2, createdAt: '2' }
      ],
      readCursorChanges: [{ userId: 'u1', oldSeq: 1, newSeq: 2 }],
      deliveredCursorChanges: [{ userId: 'u1', oldSeq: 1, newSeq: 2 }]
    }]
  }));
  const result = spawnSync(process.execPath, [
    path.join(__dirname, '..', 'tools', 'message-sequence-repair-apply.js'),
    '--source', source,
    '--target', target,
    '--secret', secretFile,
    '--plan', plan,
    '--out', report
  ], { encoding: 'utf8' });
  assert.strictEqual(result.status, 0, result.stderr || result.stdout);
  const rows = fs.readFileSync(path.join(target, 'messages', 'c1.jsonl'), 'utf8')
    .split('\n').filter(Boolean).map((line) => openMessage('apply-secret', 'c1', line, null));
  assert.deepStrictEqual(rows.map((row) => [row.id, row.seq]), [['m1', 1], ['m2', 2]]);
  assert.strictEqual(JSON.parse(fs.readFileSync(path.join(target, 'reads.json'), 'utf8'))
    .reads.u1.c1, 2);
  assert.strictEqual(JSON.parse(fs.readFileSync(report, 'utf8')).rewrittenMessages, 2);
  console.log('message-sequence-repair-apply: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
