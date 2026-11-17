#!/usr/bin/env node
'use strict';

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
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (_) {
    return fallback;
  }
}

function compareMessages(left, right) {
  return String(left.createdAt || '').localeCompare(String(right.createdAt || ''))
    || String(left.id || '').localeCompare(String(right.id || ''));
}

function remapCursor(messages, oldCursor) {
  let next = 0;
  for (const row of messages) {
    if (Number(row.oldSeq) <= oldCursor) next = Math.max(next, row.newSeq);
  }
  return next;
}

function main() {
  const dataDir = path.resolve(String(arg('data', '') || ''));
  const secretFile = path.resolve(String(arg('secret', '') || ''));
  const inventoryFile = path.resolve(String(arg('inventory', '') || ''));
  const out = path.resolve(String(arg('out', '') || ''));
  if (!dataDir || !secretFile || !inventoryFile || !out) {
    throw new Error('usage: message-sequence-repair-plan.js --data DIR '
      + '--secret FILE --inventory FILE --out FILE');
  }
  const secret = fs.readFileSync(secretFile, 'utf8').trim();
  const inventory = JSON.parse(fs.readFileSync(inventoryFile, 'utf8'));
  const chatIds = Array.from(new Set((inventory.errors || [])
    .filter((row) => row.kind === 'message-seq-duplicate'
      || row.kind === 'message-seq-gap'
      || row.kind === 'message-seq-order')
    .map((row) => String(row.id || '').split(':')[0])
    .filter(Boolean))).sort();
  let vault = null;
  if (fs.existsSync(path.join(dataDir, 'keyring.json'))) {
    vault = new SecurityVault({ dataDir, rootMaterial: secret });
  }
  const reads = readJson(path.join(dataDir, 'reads.json'), { reads: {} }).reads || {};
  const delivered = readJson(
    path.join(dataDir, 'delivered.json'),
    { delivered: {} }
  ).delivered || {};
  const chatsStore = readJson(path.join(dataDir, 'chats.json'), { chats: [] });
  const chats = Array.isArray(chatsStore.chats) ? chatsStore.chats : [];
  const chatById = new Map(chats.map((chat) => [chat.id, chat]));
  const plans = [];
  let changedMessages = 0;
  let changedReadCursors = 0;
  let changedDeliveredCursors = 0;
  const failures = [];
  for (const chatId of chatIds) {
    const file = path.join(dataDir, 'messages', chatId + '.jsonl');
    if (!fs.existsSync(file)) {
      failures.push({ code: 'missing-thread', chatId });
      continue;
    }
    const lines = fs.readFileSync(file, 'utf8').split('\n').filter((line) => line.trim());
    const messages = [];
    for (let index = 0; index < lines.length; index += 1) {
      try {
        const message = openMessage(secret, chatId, lines[index], vault);
        if (message && message.id) {
          messages.push({
            id: String(message.id),
            oldSeq: Number(message.seq) || 0,
            createdAt: String(message.createdAt || '')
          });
        }
      } catch (_) {
        failures.push({ code: 'decrypt-message', chatId, line: index + 1 });
      }
    }
    messages.sort(compareMessages);
    const rows = messages.map((message, index) => ({
      id: message.id,
      oldSeq: message.oldSeq,
      newSeq: index + 1,
      createdAt: message.createdAt
    }));
    const changed = rows.filter((row) => row.oldSeq !== row.newSeq);
    changedMessages += changed.length;
    const readChanges = [];
    for (const [userId, byChat] of Object.entries(reads)) {
      if (!Object.prototype.hasOwnProperty.call(byChat || {}, chatId)) continue;
      const oldSeq = Number(byChat[chatId]) || 0;
      const newSeq = remapCursor(rows, oldSeq);
      if (newSeq !== oldSeq) {
        changedReadCursors += 1;
        readChanges.push({ userId, oldSeq, newSeq });
      }
    }
    const deliveredChanges = [];
    for (const [userId, byChat] of Object.entries(delivered)) {
      if (!Object.prototype.hasOwnProperty.call(byChat || {}, chatId)) continue;
      const oldSeq = Number(byChat[chatId]) || 0;
      const newSeq = remapCursor(rows, oldSeq);
      if (newSeq !== oldSeq) {
        changedDeliveredCursors += 1;
        deliveredChanges.push({ userId, oldSeq, newSeq });
      }
    }
    const chat = chatById.get(chatId);
    plans.push({
      chatId,
      messageCount: rows.length,
      oldChatSeq: Number(chat && chat.seq) || 0,
      newChatSeq: rows.length,
      changedMessages: changed.length,
      readCursorChanges: readChanges,
      deliveredCursorChanges: deliveredChanges,
      rows
    });
  }
  const report = {
    version: 1,
    ok: failures.length === 0,
    generatedAt: new Date().toISOString(),
    dataDir,
    affectedChats: chatIds.length,
    plannedChats: plans.length,
    changedMessages,
    changedReadCursors,
    changedDeliveredCursors,
    failures,
    planHash: hash(plans),
    plans
  };
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out + '.tmp', JSON.stringify(report, null, 2), 'utf8');
  fs.renameSync(out + '.tmp', out);
  console.log(JSON.stringify({
    ok: report.ok,
    affectedChats: report.affectedChats,
    plannedChats: report.plannedChats,
    changedMessages: report.changedMessages,
    changedReadCursors: report.changedReadCursors,
    changedDeliveredCursors: report.changedDeliveredCursors,
    failures: report.failures,
    planHash: report.planHash,
    out
  }, null, 2));
  if (!report.ok) process.exitCode = 2;
}

if (require.main === module) {
  try { main(); }
  catch (error) {
    console.error(error.stack || error);
    process.exitCode = 1;
  }
}

module.exports = { main };
