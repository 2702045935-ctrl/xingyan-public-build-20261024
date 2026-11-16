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

function readJson(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch (_) { return fallback; }
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file + '.tmp', JSON.stringify(value, null, 2), 'utf8');
  fs.renameSync(file + '.tmp', file);
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

function applyCursorChanges(store, key, changes) {
  for (const change of changes) {
    if (!store[change.userId]) store[change.userId] = {};
    store[change.userId][key] = change.newSeq;
  }
}

function main() {
  const sourceDir = path.resolve(String(arg('source', '') || ''));
  const targetDir = path.resolve(String(arg('target', '') || ''));
  const secretFile = path.resolve(String(arg('secret', '') || ''));
  const planFile = path.resolve(String(arg('plan', '') || ''));
  const out = path.resolve(String(arg('out', '') || ''));
  if (!sourceDir || !targetDir || !secretFile || !planFile || !out) {
    throw new Error('usage: message-sequence-repair-apply.js --source DIR '
      + '--target DIR --secret FILE --plan FILE --out FILE');
  }
  if (sourceDir === targetDir) throw new Error('target must differ from source');
  fs.mkdirSync(path.join(targetDir, 'messages'), { recursive: true });
  const secret = fs.readFileSync(secretFile, 'utf8').trim();
  const plan = JSON.parse(fs.readFileSync(planFile, 'utf8'));
  if (!plan.ok) throw new Error('repair plan is not clean');
  let vault = null;
  if (fs.existsSync(path.join(sourceDir, 'keyring.json'))) {
    vault = new SecurityVault({ dataDir: sourceDir, rootMaterial: secret });
  }
  const chatsStore = readJson(path.join(sourceDir, 'chats.json'), { chats: [] });
  const readsStore = readJson(path.join(sourceDir, 'reads.json'), { reads: {}, cleared: {} });
  const deliveredStore = readJson(
    path.join(sourceDir, 'delivered.json'),
    { delivered: {} }
  );
  const chatById = new Map((chatsStore.chats || []).map((chat) => [chat.id, chat]));
  let rewrittenMessages = 0;
  for (const item of plan.plans) {
    const sourceFile = path.join(sourceDir, 'messages', item.chatId + '.jsonl');
    const targetFile = path.join(targetDir, 'messages', item.chatId + '.jsonl');
    const lines = fs.readFileSync(sourceFile, 'utf8').split('\n').filter((line) => line.trim());
    const messages = new Map();
    for (const line of lines) {
      const message = openMessage(secret, item.chatId, line, vault);
      if (message && message.id) messages.set(String(message.id), message);
    }
    const output = [];
    for (const row of item.rows) {
      const message = messages.get(row.id);
      if (!message) throw new Error('message missing from source: ' + item.chatId + ':' + row.id);
      message.seq = row.newSeq;
      output.push(sealMessage(secret, item.chatId, message));
      rewrittenMessages += 1;
    }
    fs.writeFileSync(targetFile, output.join('\n') + '\n', 'utf8');
    const chat = chatById.get(item.chatId);
    if (chat) chat.seq = item.newChatSeq;
    applyCursorChanges(readsStore.reads || (readsStore.reads = {}),
      item.chatId, item.readCursorChanges || []);
    applyCursorChanges(deliveredStore.delivered || (deliveredStore.delivered = {}),
      item.chatId, item.deliveredCursorChanges || []);
  }
  writeJson(path.join(targetDir, 'chats.json'), chatsStore);
  writeJson(path.join(targetDir, 'reads.json'), readsStore);
  writeJson(path.join(targetDir, 'delivered.json'), deliveredStore);
  fs.copyFileSync(secretFile, path.join(targetDir, 'secret.key'));
  if (fs.existsSync(path.join(sourceDir, 'keyring.json'))) {
    fs.copyFileSync(path.join(sourceDir, 'keyring.json'), path.join(targetDir, 'keyring.json'));
  }
  const report = {
    version: 1,
    ok: true,
    generatedAt: new Date().toISOString(),
    sourceDir,
    targetDir,
    affectedChats: plan.plannedChats,
    rewrittenMessages,
    changedReadCursors: plan.changedReadCursors,
    changedDeliveredCursors: plan.changedDeliveredCursors,
    planHash: plan.planHash,
    chatsHash: hash(chatsStore.chats || []),
    readsHash: hash(readsStore.reads || {}),
    deliveredHash: hash(deliveredStore.delivered || {})
  };
  writeJson(out, report);
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
