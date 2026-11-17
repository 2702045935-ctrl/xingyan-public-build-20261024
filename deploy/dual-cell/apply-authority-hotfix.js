#!/usr/bin/env node
'use strict';

const fs = require('fs');

const sourceFile = process.argv[2];
const outputFile = process.argv[3];
if (!sourceFile || !outputFile) {
  throw new Error('usage: apply-authority-hotfix.js SOURCE OUTPUT');
}

let source = fs.readFileSync(sourceFile, 'utf8');

function replaceOnce(before, after, label) {
  const index = source.indexOf(before);
  if (index < 0) throw new Error('missing hotfix anchor: ' + label);
  if (source.indexOf(before, index + before.length) >= 0) {
    throw new Error('duplicate hotfix anchor: ' + label);
  }
  source = source.slice(0, index) + after + source.slice(index + before.length);
}

function replaceAll(before, after, label, expectedCount) {
  const parts = source.split(before);
  const count = parts.length - 1;
  if (count !== expectedCount) {
    throw new Error('unexpected hotfix count for ' + label + ': ' + count);
  }
  source = parts.join(after);
}

replaceOnce(
  "const { createSecurityVault } = require('./lib/security-vault');",
  "const { createSecurityVault } = require('./lib/security-vault');\n"
    + "const { ShardAuthorityStore } = require('./lib/shard-authority-store');\n"
    + "const { ShardAuthorityRuntime } = require('./lib/shard-authority-runtime');",
  'authority modules'
);

replaceOnce(
  'let chatRoutePlanEnforced = false;',
  'let chatRoutePlanEnforced = false;\nlet shardAuthorityRuntime = null;',
  'authority runtime global'
);

replaceOnce(
  'function saveMessagesFile(chatId, list) {\n'
    + '  if (GW_MODE) { __cancelMsgWrite(chatId); return; }\n',
  'function authorityChatState(chat) {\n'
    + '  if (!chat) return {};\n'
    + '  return {\n'
    + '    chatId: String(chat.id || ""),\n'
    + '    type: String(chat.type || "direct"),\n'
    + '    title: String(chat.title || ""),\n'
    + '    memberIds: Array.isArray(chat.memberIds) ? chat.memberIds.slice() : []\n'
    + '  };\n'
    + '}\n\n'
    + 'function saveMessagesFile(chatId, list) {\n'
    + '  if (GW_MODE) { __cancelMsgWrite(chatId); return; }\n'
    + '  if (shardAuthorityRuntime && shardAuthorityRuntime.appliesTo(chatId)) {\n'
    + '    const chat = db.chats.find((item) => item.id === chatId);\n'
    + '    const result = shardAuthorityRuntime.replaceMessages(chatId, list, authorityChatState(chat));\n'
    + '    if (result.status === "fenced") throw new Error("authority writer is fenced");\n'
    + '  }\n',
  'transcript rewrite'
);

replaceOnce(
  'function loadMessages(chatId) {\n'
    + '  if (messageCache.has(chatId)) {',
  'function loadMessages(chatId) {\n'
    + '  if (shardAuthorityRuntime && shardAuthorityRuntime.appliesTo(chatId)) {\n'
    + '    const list = shardAuthorityRuntime.readMessages(chatId) || [];\n'
    + '    const trimmed = list.slice(-MAX_CACHE);\n'
    + '    messageCache.set(chatId, trimmed);\n'
    + '    while (messageCache.size > MESSAGE_CACHE_MAX_CHATS) {\n'
    + '      const oldest = messageCache.keys().next().value;\n'
    + '      if (oldest === chatId) break;\n'
    + '      messageCache.delete(oldest);\n'
    + '    }\n'
    + '    return trimmed;\n'
    + '  }\n'
    + '  if (messageCache.has(chatId)) {',
  'authority read'
);

replaceOnce(
  'function setClearedSeq(userId, chatId, seq) {\n'
    + '  if (!db.cleared[userId]) db.cleared[userId] = {};\n'
    + '  invalidateChatListCache();\n'
    + '  if (!MULTI_SHARD || userShardOf(userId) === SHARD_ID) { db.cleared[userId][chatId] = seq; readsDirty = true; return; }\n'
    + '  db.cleared[userId][chatId] = seq;\n'
    + "  BUS.sendToShard(shardName(userShardOf(userId)), { type: 'clearpatch', u: userId, c: chatId, seq: seq });\n"
    + '}',
  'function clearedSeqFor(userId, chatId) {\n'
    + '  const local = Number((((db.cleared || {})[userId] || {})[chatId]) || 0);\n'
    + '  const authoritative = shardAuthorityRuntime\n'
    + '    && typeof shardAuthorityRuntime.clearCursor === "function"\n'
    + '    ? Number(shardAuthorityRuntime.clearCursor(userId, chatId) || 0)\n'
    + '    : 0;\n'
    + '  return Math.max(local, authoritative);\n'
    + '}\n'
    + 'function setClearedSeq(userId, chatId, seq) {\n'
    + '  const value = Math.max(0, Math.floor(Number(seq) || 0));\n'
    + '  if (shardAuthorityRuntime\n'
    + '      && typeof shardAuthorityRuntime.setClearCursor === "function") {\n'
    + '    const result = shardAuthorityRuntime.setClearCursor(userId, chatId, value);\n'
    + '    if (result && result.status === "fenced") {\n'
    + '      throw new Error("authority writer is fenced");\n'
    + '    }\n'
    + '  }\n'
    + '  if (!db.cleared[userId]) db.cleared[userId] = {};\n'
    + '  invalidateChatListCache();\n'
    + '  if (!MULTI_SHARD || userShardOf(userId) === SHARD_ID) {\n'
    + '    db.cleared[userId][chatId] = value; readsDirty = true; return value;\n'
    + '  }\n'
    + '  db.cleared[userId][chatId] = value;\n'
    + "  BUS.sendToShard(shardName(userShardOf(userId)), { type: 'clearpatch', u: userId, c: chatId, seq: value });\n"
    + '  return value;\n'
    + '}',
  'authority clear cursor'
);

replaceOnce(
  "    const clearedSeq = (((db.cleared || {})[forUserId]) || {})[chat.id] || 0;",
  '    const clearedSeq = clearedSeqFor(forUserId, chat.id);',
  'chat summary clear cursor'
);

replaceAll(
  'const clearedSeq = ((db.cleared || {})[user.id] || {})[chat.id] || 0;',
  'const clearedSeq = clearedSeqFor(user.id, chat.id);',
  'message clear cursor reads',
  3
);

replaceOnce(
  '          const messages = loadMessages(chat.id);\n'
    + '          const clearedSeq = messages.length ? messages[messages.length - 1].seq : 0;\n'
    + '          if (!db.cleared[user.id]) db.cleared[user.id] = {};\n'
    + '          db.cleared[user.id][chat.id] = clearedSeq;\n'
    + '          if (!db.reads[user.id]) db.reads[user.id] = {};\n'
    + '          db.reads[user.id][chat.id] = clearedSeq;\n',
  '          const messages = loadMessages(chat.id);\n'
    + '          const clearedSeq = messages.length ? messages[messages.length - 1].seq : 0;\n'
    + '          setClearedSeq(user.id, chat.id, clearedSeq);\n'
    + '          if (!db.reads[user.id]) db.reads[user.id] = {};\n'
    + '          db.reads[user.id][chat.id] = clearedSeq;\n',
  'friend removal clear cursor'
);

replaceOnce(
  '      const messages = loadMessages(chat.id);\n'
    + '      clearedSeq = messages.length ? messages[messages.length - 1].seq : 0;\n'
    + '      if (!db.cleared[user.id]) db.cleared[user.id] = {};\n'
    + '      db.cleared[user.id][chat.id] = clearedSeq;\n'
    + '      if (!db.reads[user.id]) db.reads[user.id] = {};\n'
    + '      db.reads[user.id][chat.id] = clearedSeq;\n',
  '      const messages = loadMessages(chat.id);\n'
    + '      clearedSeq = messages.length ? messages[messages.length - 1].seq : 0;\n'
    + '      setClearedSeq(user.id, chat.id, clearedSeq);\n'
    + '      if (!db.reads[user.id]) db.reads[user.id] = {};\n'
    + '      db.reads[user.id][chat.id] = clearedSeq;\n',
  'delete chat clear cursor'
);

replaceOnce(
  'function loadAllMessagesForSearch(chatId) {\n'
    + '  const file = messagesFile(chatId);',
  'function loadAllMessagesForSearch(chatId) {\n'
    + '  if (shardAuthorityRuntime && shardAuthorityRuntime.appliesTo(chatId)) {\n'
    + '    return shardAuthorityRuntime.readMessages(chatId) || [];\n'
    + '  }\n'
    + '  const file = messagesFile(chatId);',
  'authority search read'
);

replaceOnce(
  'function appendMessage(chatId, message) {\n'
    + '  invalidateChatListCache();\n'
    + '  if (!GW_MODE) __queueMsgWrite(chatId, sealMessage(chatId, message) + \'\\n\');',
  'function appendMessage(chatId, message) {\n'
    + '  invalidateChatListCache();\n'
    + '  if (shardAuthorityRuntime && shardAuthorityRuntime.appliesTo(chatId)) {\n'
    + '    const chat = db.chats.find((item) => item.id === chatId);\n'
    + '    const authoritative = shardAuthorityRuntime.appendMessage(\n'
    + '      chatId, message, authorityChatState(chat)\n'
    + '    );\n'
    + '    if (authoritative.status === "fenced") {\n'
    + '      throw new Error("authority writer is fenced");\n'
    + '    }\n'
    + '    Object.keys(message).forEach((key) => { delete message[key]; });\n'
    + '    Object.assign(message, authoritative.message);\n'
    + '    if (authoritative.status === "duplicate") {\n'
    + '      Object.defineProperty(message, "__authorityDuplicate", {\n'
    + '        value: true, configurable: true\n'
    + '      });\n'
    + '      return;\n'
    + '    }\n'
    + '  }\n'
    + '  if (!GW_MODE) __queueMsgWrite(chatId, sealMessage(chatId, message) + \'\\n\');',
  'authority append'
);

const authorityInit = `
const __authorityEnabled = ['1', 'true', 'on'].includes(
  String(process.env.SHARD_AUTHORITY_ENABLED || '0').toLowerCase()
) && String(process.env.SHARD_AUTHORITY_SHARDS
  || process.env.SHARD_AUTHORITY_SHARD
  || '').split(',').map((value) => value.trim())
  .includes(String(process.env.SHARD_ID || '0'));
if (__authorityEnabled) {
  try {
    const authorityShard = Number(process.env.SHARD_ID || 0);
    const authorityEpoch = Math.max(1, Number(process.env.SHARD_AUTHORITY_EPOCH || 1) || 1);
    const authorityTopology = String(process.env.SHARD_TOPOLOGY_ID
      || (chatRoutePlan && chatRoutePlan.topologyId) || '');
    if (!authorityTopology) throw new Error('authority topology is missing');
    const authorityDatabase = path.resolve(String(process.env.SHARD_AUTHORITY_DB_FILE
      || path.join(DATA_DIR, 'shard-authority.sqlite3')));
    const authorityStore = new ShardAuthorityStore({
      shardId: authorityShard,
      topologyId: authorityTopology,
      databaseFile: authorityDatabase,
      leaseManager: {
        validate(shard) {
          if (Number(shard) !== authorityShard) return { ok: false, reason: 'not-owner' };
          if (String(process.env.SHARD_WRITE_FROZEN || '') === '1') {
            return { ok: false, reason: 'write-frozen' };
          }
          return { ok: true, lease: {
            shard: authorityShard,
            ownerId: String(process.env.DUAL_CELL_ID || ('shard-' + authorityShard)),
            epoch: authorityEpoch
          } };
        }
      },
      now: () => new Date().toISOString()
    });
    shardAuthorityRuntime = new ShardAuthorityRuntime({
      store: authorityStore,
      readEnabled: ['1', 'true', 'on'].includes(
        String(process.env.SHARD_AUTHORITY_READ || '1').toLowerCase()
      ),
      writeEnabled: ['1', 'true', 'on'].includes(
        String(process.env.SHARD_AUTHORITY_WRITE || '1').toLowerCase()
      ),
      isDirectChat(chatId) {
        const chat = (db.chats || []).find((item) => item.id === chatId);
        return !!chat && chat.type !== 'group'
          && (!Array.isArray(chat.memberIds) || chat.memberIds.length <= 2);
      }
    });
    console.log('[分片权威] enabled shard=' + authorityShard
      + ' topology=' + authorityTopology + ' epoch=' + authorityEpoch
      + ' read=' + shardAuthorityRuntime.readEnabled
      + ' write=' + shardAuthorityRuntime.writeEnabled);
  } catch (error) {
    if (['1', 'true', 'on'].includes(
      String(process.env.SHARD_AUTHORITY_REQUIRED || '0').toLowerCase()
    )) throw error;
    shardAuthorityRuntime = null;
    console.log('[分片权威] disabled: ' + String(error && error.message || error));
  }
}
`;

replaceOnce(
  'loadStore();\nwarmMessageCaches();',
  'loadStore();\n' + authorityInit + '\nwarmMessageCaches();',
  'authority startup'
);

fs.mkdirSync(require('path').dirname(outputFile), { recursive: true });
fs.writeFileSync(outputFile + '.tmp', source, 'utf8');
fs.renameSync(outputFile + '.tmp', outputFile);
console.log('authority hotfix applied: ' + outputFile);
