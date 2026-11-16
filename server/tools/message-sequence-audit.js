#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { openMessage } = require('../lib/shard-data-inventory');
const { SecurityVault } = require('../lib/security-vault');
const { canonical, hash } = require('../lib/shard-snapshot');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function contentHash(message) {
  return hash({
    senderId: message.senderId || '',
    kind: message.kind || '',
    content: message.content === undefined ? '' : message.content,
    createdAt: message.createdAt || ''
  });
}

function classify(rows) {
  const ids = new Set(rows.map((row) => String(row.id || '')).filter(Boolean));
  const hashes = new Set(rows.map(contentHash));
  if (ids.size <= 1) return 'same-id';
  if (hashes.size <= 1) return 'same-content';
  return 'different-content';
}

function main() {
  const dataDir = path.resolve(String(arg('data', '') || ''));
  const secretFile = path.resolve(String(arg('secret', '') || ''));
  const out = path.resolve(String(arg('out', '') || ''));
  const inventoryFile = String(arg('inventory', '') || '');
  if (!dataDir || !secretFile || !out) {
    throw new Error('usage: message-sequence-audit.js --data DIR --secret FILE --out FILE');
  }
  const secret = fs.readFileSync(secretFile, 'utf8').trim();
  let vault = null;
  if (fs.existsSync(path.join(dataDir, 'keyring.json'))) {
    vault = new SecurityVault({ dataDir, rootMaterial: secret });
  }
  const messagesDir = path.join(dataDir, 'messages');
  let files = fs.existsSync(messagesDir)
    ? fs.readdirSync(messagesDir).filter((name) => name.endsWith('.jsonl')).sort()
    : [];
  let scopedChats = [];
  if (inventoryFile) {
    const inventory = JSON.parse(fs.readFileSync(path.resolve(inventoryFile), 'utf8'));
    scopedChats = Array.from(new Set((inventory.errors || [])
      .filter((row) => row.kind === 'message-seq-duplicate')
      .map((row) => String(row.id || '').split(':')[0])
      .filter(Boolean))).sort();
    const allowed = new Set(scopedChats.map((chatId) => chatId + '.jsonl'));
    files = files.filter((name) => allowed.has(name));
  }
  const chats = [];
  const classes = {
    'same-id': 0,
    'same-content': 0,
    'different-content': 0
  };
  let totalMessages = 0;
  let duplicateGroups = 0;
  let duplicateMessages = 0;
  for (const name of files) {
    const chatId = name.slice(0, -'.jsonl'.length);
    const lines = fs.readFileSync(path.join(messagesDir, name), 'utf8')
      .split('\n').filter((line) => line.trim());
    const bySeq = new Map();
    for (let index = 0; index < lines.length; index += 1) {
      let message;
      try {
        message = openMessage(secret, chatId, lines[index], vault);
      } catch (_) {
        continue;
      }
      if (!message || !message.id) continue;
      totalMessages += 1;
      const seq = Number(message.seq);
      if (!Number.isFinite(seq) || seq <= 0) continue;
      if (!bySeq.has(seq)) bySeq.set(seq, []);
      bySeq.get(seq).push(message);
    }
    const groups = [];
    for (const [seq, rows] of Array.from(bySeq.entries()).sort((a, b) => a[0] - b[0])) {
      if (rows.length <= 1) continue;
      const kind = classify(rows);
      classes[kind] += 1;
      duplicateGroups += 1;
      duplicateMessages += rows.length - 1;
      groups.push({
        seq,
        kind,
        count: rows.length,
        samples: rows.slice(0, 10).map((message) => ({
          id: message.id,
          senderId: message.senderId || '',
          kind: message.kind || '',
          createdAt: message.createdAt || '',
          content: String(message.content || '').slice(0, 120),
          contentHash: contentHash(message)
        }))
      });
    }
    if (groups.length) {
      chats.push({
        chatId,
        fileMessages: lines.length,
        duplicateGroups: groups.length,
        duplicateMessages: groups.reduce((sum, group) => sum + group.count - 1, 0),
        classes: {
          'same-id': groups.filter((group) => group.kind === 'same-id').length,
          'same-content': groups.filter((group) => group.kind === 'same-content').length,
          'different-content': groups.filter((group) => group.kind === 'different-content').length
        },
        groups: groups.slice(0, 100)
      });
    }
  }
  const report = {
    version: 1,
    ok: classes['different-content'] === 0,
    generatedAt: new Date().toISOString(),
    dataDir,
    inventoryFile: inventoryFile ? path.resolve(inventoryFile) : '',
    scopedChats: scopedChats.length,
    messageThreads: files.length,
    totalMessages,
    chatsWithDuplicates: chats.length,
    duplicateGroups,
    duplicateMessages,
    classes,
    chats
  };
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out + '.tmp', JSON.stringify(report, null, 2), 'utf8');
  fs.renameSync(out + '.tmp', out);
  console.log(JSON.stringify({
    ok: report.ok,
    messageThreads: report.messageThreads,
    totalMessages: report.totalMessages,
    chatsWithDuplicates: report.chatsWithDuplicates,
    duplicateGroups: report.duplicateGroups,
    duplicateMessages: report.duplicateMessages,
    classes: report.classes,
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
