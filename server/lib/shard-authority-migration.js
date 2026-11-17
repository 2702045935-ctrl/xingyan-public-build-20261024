'use strict';

const fs = require('fs');
const path = require('path');
const { SecurityVault } = require('./security-vault');
const { openMessage } = require('./shard-data-inventory');

function readJson(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (_) {
    return fallback;
  }
}

function isDirectChat(chat) {
  if (!chat || chat.type === 'group') return false;
  return !Array.isArray(chat.memberIds) || chat.memberIds.length <= 2;
}

function stableOrder(left, right) {
  return String(left.createdAt || '').localeCompare(String(right.createdAt || ''))
    || String(left.id || '').localeCompare(String(right.id || ''));
}

function loadShardSnapshot(options) {
  const rawDataDir = String(options && options.dataDir || '');
  const rawSecretFile = String(options && options.secretFile || '');
  if (!rawDataDir) throw new Error('dataDir is required');
  if (!rawSecretFile) throw new Error('secretFile is required');
  const dataDir = path.resolve(rawDataDir);
  const secretFile = path.resolve(rawSecretFile);
  const secret = fs.readFileSync(secretFile, 'utf8').trim();
  if (!secret) throw new Error('secretFile is empty');
  const keyringFile = path.join(dataDir, 'keyring.json');
  const vault = fs.existsSync(keyringFile)
    ? new SecurityVault({ dataDir, rootMaterial: secret })
    : null;
  const chatsStore = readJson(path.join(dataDir, 'chats.json'), { chats: [] });
  const chats = (Array.isArray(chatsStore.chats) ? chatsStore.chats : [])
    .filter((chat) => chat && chat.id)
    .filter((chat) => options && options.directOnly === false || isDirectChat(chat));
  const snapshots = [];
  const skipped = [];
  for (const chat of chats) {
    const file = path.join(dataDir, 'messages', chat.id + '.jsonl');
    if (!fs.existsSync(file)) {
      skipped.push({ chatId: chat.id, reason: 'missing-thread' });
      continue;
    }
    const messages = [];
    const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/).filter(Boolean);
    for (let index = 0; index < lines.length; index += 1) {
      try {
        const message = openMessage(secret, chat.id, lines[index], vault);
        if (message && message.id) messages.push(message);
      } catch (_) {
        throw new Error('cannot decrypt ' + chat.id + ' line ' + (index + 1));
      }
    }
    messages.sort(stableOrder);
    const normalized = messages.map((message, index) => Object.assign({}, message, {
      chatId: chat.id,
      seq: index + 1
    }));
    const last = normalized[normalized.length - 1];
    snapshots.push({
      chatId: String(chat.id),
      messages: normalized,
      chatState: {
        chatId: String(chat.id),
        type: String(chat.type || 'direct'),
        title: String(chat.title || ''),
        memberIds: Array.isArray(chat.memberIds) ? chat.memberIds.slice() : [],
        lastMessageId: last ? String(last.id) : '',
        lastMessageAt: last ? String(last.createdAt || '') : ''
      }
    });
  }
  return {
    dataDir,
    directOnly: options && options.directOnly !== false,
    chats: snapshots.length,
    messages: snapshots.reduce((sum, chat) => sum + chat.messages.length, 0),
    skipped,
    snapshots
  };
}

function importShardSnapshot(store, snapshot) {
  if (!store || typeof store.importChatSnapshot !== 'function') {
    throw new Error('authority store is required');
  }
  const imported = [];
  for (const chat of snapshot.snapshots || []) {
    const result = store.importChatSnapshot(
      chat.chatId,
      chat.messages,
      chat.chatState
    );
    if (result.status === 'fenced') {
      throw new Error('authority writer is fenced');
    }
    imported.push({
      chatId: chat.chatId,
      status: result.status,
      messages: result.imported || 0
    });
  }
  const verification = store.verify();
  return {
    ok: verification.ok,
    chats: imported.length,
    messages: imported.reduce((sum, row) => sum + row.messages, 0),
    imported,
    verification
  };
}

module.exports = {
  isDirectChat,
  loadShardSnapshot,
  importShardSnapshot
};
