#!/usr/bin/env node
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { openMessage } = require('../lib/shard-data-inventory');
const { SecurityVault } = require('../lib/security-vault');
const { hash } = require('../lib/shard-snapshot');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function messageKey(secret, chatId) {
  return crypto.createHmac('sha256', String(secret || '')).update('msg:' + chatId).digest();
}

function sealMessage(secret, chatId, message) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', messageKey(secret, chatId), iv);
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
}

function main() {
  const sourceDir = path.resolve(String(arg('source', '') || ''));
  const targetDir = path.resolve(String(arg('target', '') || ''));
  const secretFile = path.resolve(String(arg('secret', '') || ''));
  const planFile = path.resolve(String(arg('plan', '') || ''));
  const out = path.resolve(String(arg('out', '') || ''));
  if (!sourceDir || !targetDir || !secretFile || !planFile || !out) {
    throw new Error('usage: upload-reference-quarantine-apply.js --source DIR '
      + '--target DIR --secret FILE --plan FILE --out FILE');
  }
  if (sourceDir === targetDir) throw new Error('target must differ from source');
  const secret = fs.readFileSync(secretFile, 'utf8').trim();
  const plan = JSON.parse(fs.readFileSync(planFile, 'utf8'));
  let vault = null;
  if (fs.existsSync(path.join(targetDir, 'keyring.json'))) {
    vault = new SecurityVault({ dataDir: targetDir, rootMaterial: secret });
  } else if (fs.existsSync(path.join(sourceDir, 'keyring.json'))) {
    fs.copyFileSync(path.join(sourceDir, 'keyring.json'), path.join(targetDir, 'keyring.json'));
    vault = new SecurityVault({ dataDir: targetDir, rootMaterial: secret });
  }
  const byChat = new Map();
  for (const item of plan.items || []) {
    for (const reference of item.references || []) {
      if (!byChat.has(reference.chatId)) byChat.set(reference.chatId, []);
      byChat.get(reference.chatId).push(reference);
    }
  }
  let quarantineMessages = 0;
  let recoveryPendingMessages = 0;
  const touched = [];
  for (const [chatId, references] of byChat.entries()) {
    const filename = chatId + '.jsonl';
    const sourceFile = path.join(sourceDir, 'messages', filename);
    const targetFile = path.join(targetDir, 'messages', filename);
    if (!fs.existsSync(targetFile)) {
      fs.mkdirSync(path.dirname(targetFile), { recursive: true });
      fs.copyFileSync(sourceFile, targetFile);
    }
    const lines = fs.readFileSync(targetFile, 'utf8').split('\n').filter((line) => line.trim());
    const messages = new Map();
    for (const line of lines) {
      const message = openMessage(secret, chatId, line, vault);
      if (message && message.id) messages.set(String(message.id), message);
    }
    for (const reference of references) {
      const message = messages.get(String(reference.messageId));
      if (!message) throw new Error('message missing: ' + chatId + ':' + reference.messageId);
      const pending = path.basename(reference.path) === 'x.mp3';
      if (pending) {
        message.mediaUnavailable = true;
        message.recoveryPending = true;
        recoveryPendingMessages += 1;
      } else {
        message.originalKind = message.kind || '';
        message.kind = 'text';
        message.content = '[媒体内容已丢失]';
        message.mediaUnavailable = true;
        message.unavailableMedia = {
          kind: message.originalKind,
          path: reference.path
        };
        quarantineMessages += 1;
      }
    }
    const output = Array.from(messages.values())
      .sort((left, right) => Number(left.seq) - Number(right.seq)
        || String(left.id).localeCompare(String(right.id)))
      .map((message) => sealMessage(secret, chatId, message));
    fs.writeFileSync(targetFile, output.join('\n') + '\n', 'utf8');
    touched.push(chatId);
  }
  const report = {
    version: 1,
    ok: true,
    generatedAt: new Date().toISOString(),
    sourceDir,
    targetDir,
    touchedChats: touched.length,
    quarantineMessages,
    recoveryPendingMessages,
    planHash: plan.planHash,
    targetHash: hash({
      touched: touched.sort(),
      quarantineMessages,
      recoveryPendingMessages
    })
  };
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out + '.tmp', JSON.stringify(report, null, 2), 'utf8');
  fs.renameSync(out + '.tmp', out);
  console.log(JSON.stringify(report, null, 2));
}

if (require.main === module) {
  try { main(); }
  catch (error) {
    console.error(error.stack || error);
    process.exitCode = 1;
  }
}

module.exports = { main };
