'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { ownerFor } = require('./shard-placement-plan');
const { verifyRoutePlan } = require('./shard-route-plan');
const { verifyPhysicalLayout } = require('./shard-physical-layout');

function readJson(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (_) {
    return fallback;
  }
}

function rowsOf(value, key) {
  if (Array.isArray(value)) return value;
  return value && Array.isArray(value[key]) ? value[key] : [];
}

function stable(value) {
  if (value === null || typeof value !== 'object') {
    return JSON.stringify(value === undefined ? null : value);
  }
  if (Array.isArray(value)) return '[' + value.map(stable).join(',') + ']';
  return '{' + Object.keys(value).sort().map((key) =>
    JSON.stringify(key) + ':' + stable(value[key])
  ).join(',') + '}';
}

function digest(value) {
  return crypto.createHash('sha256').update(stable(value)).digest('hex');
}

function safeId(value, label) {
  const id = String(value || '');
  if (!id || id !== path.basename(id) || id.indexOf('/') >= 0 || id.indexOf('\\') >= 0) {
    throw new Error('unsafe ' + label + ': ' + id);
  }
  return id;
}

class PhysicalShardReader {
  constructor(options) {
    const opts = options || {};
    this.root = path.resolve(String(opts.root || ''));
    this.routePlan = opts.routePlan;
    const verification = verifyRoutePlan(this.routePlan);
    if (!verification.ok) throw new Error('route plan is invalid');
    this.shardCount = Number(this.routePlan.shardCount);
    this.cache = new Map();
  }

  shardDir(shardId) {
    return path.join(this.root, 'shards', String(shardId));
  }

  readShardJson(shardId, name) {
    const key = shardId + ':' + name;
    if (!this.cache.has(key)) {
      this.cache.set(key, readJson(path.join(this.shardDir(shardId), name), null));
    }
    return this.cache.get(key);
  }

  owner(kind, id) {
    return ownerFor(this.routePlan, this.shardCount, kind, id);
  }

  readUser(id) {
    const key = safeId(id, 'user id');
    const shard = this.owner('user', key);
    return rowsOf(this.readShardJson(shard, 'users.json'), 'users')
      .find((row) => row.id === key) || null;
  }

  readChat(id) {
    const key = safeId(id, 'chat id');
    const shard = this.owner('chat', key);
    return rowsOf(this.readShardJson(shard, 'chats.json'), 'chats')
      .find((row) => row.id === key) || null;
  }

  readReadCursor(userId, chatId) {
    const uid = safeId(userId, 'user id');
    const cid = safeId(chatId, 'chat id');
    const routeId = cid + '|' + uid;
    const shard = this.owner('snapshot_reads', routeId);
    const value = this.readShardJson(shard, 'reads.json');
    return value && value.reads && value.reads[uid]
      ? value.reads[uid][cid]
      : undefined;
  }

  readFriendMeta(ownerId, friendId) {
    const owner = safeId(ownerId, 'user id');
    const friend = safeId(friendId, 'friend id');
    const routeId = owner + '|' + friend;
    const shard = this.owner('snapshot_friendMeta', routeId);
    const value = this.readShardJson(shard, 'friendmeta.json');
    return value && value.byOwner && value.byOwner[owner]
      ? value.byOwner[owner][friend]
      : undefined;
  }

  readMoment(id) {
    const key = safeId(id, 'moment id');
    const shard = this.owner('moment', key);
    return rowsOf(this.readShardJson(shard, 'moments.json'), 'moments')
      .find((row) => row.id === key) || null;
  }

  messageFile(chatId) {
    const key = safeId(chatId, 'chat id');
    return path.join(this.shardDir(this.owner('chat', key)), 'messages', key + '.jsonl');
  }

  readMessages(chatId) {
    const file = this.messageFile(chatId);
    if (!fs.existsSync(file)) return [];
    return fs.readFileSync(file, 'utf8').split('\n').filter(Boolean).map((line, index) => {
      try { return JSON.parse(line); }
      catch (_) { throw new Error('invalid message JSON: ' + chatId + ':' + (index + 1)); }
    });
  }

  messageHash(chatId) {
    const file = this.messageFile(chatId);
    return fs.existsSync(file)
      ? crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')
      : '';
  }
}

class LegacyDataReader {
  constructor(root) {
    this.root = path.resolve(String(root || ''));
    this.cache = new Map();
  }

  readJson(name) {
    if (!this.cache.has(name)) {
      this.cache.set(name, readJson(path.join(this.root, name), null));
    }
    return this.cache.get(name);
  }

  readUser(id) {
    return rowsOf(this.readJson('users.json'), 'users').find((row) => row.id === id) || null;
  }

  readChat(id) {
    return rowsOf(this.readJson('chats.json'), 'chats').find((row) => row.id === id) || null;
  }

  readReadCursor(userId, chatId) {
    const value = this.readJson('reads.json');
    return value && value.reads && value.reads[userId]
      ? value.reads[userId][chatId]
      : undefined;
  }

  readFriendMeta(ownerId, friendId) {
    const value = this.readJson('friendmeta.json');
    return value && value.byOwner && value.byOwner[ownerId]
      ? value.byOwner[ownerId][friendId]
      : undefined;
  }

  readMoment(id) {
    return rowsOf(this.readJson('moments.json'), 'moments')
      .find((row) => row.id === id) || null;
  }

  messageFile(chatId) {
    return path.join(this.root, 'messages', safeId(chatId, 'chat id') + '.jsonl');
  }

  readMessages(chatId) {
    const file = this.messageFile(chatId);
    if (!fs.existsSync(file)) return [];
    return fs.readFileSync(file, 'utf8').split('\n').filter(Boolean).map((line, index) => {
      try { return JSON.parse(line); }
      catch (_) { throw new Error('invalid message JSON: ' + chatId + ':' + (index + 1)); }
    });
  }

  messageHash(chatId) {
    const file = this.messageFile(chatId);
    return fs.existsSync(file)
      ? crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')
      : '';
  }
}

function runShadowReadAudit(options) {
  const opts = options || {};
  const source = new LegacyDataReader(opts.sourceDir);
  const physical = new PhysicalShardReader({
    root: opts.physicalRoot,
    routePlan: opts.routePlan
  });
  const layout = verifyPhysicalLayout({
    root: opts.physicalRoot,
    routePlan: opts.routePlan
  });
  const users = rowsOf(source.readJson('users.json'), 'users');
  const chats = rowsOf(source.readJson('chats.json'), 'chats');
  const moments = rowsOf(source.readJson('moments.json'), 'moments');
  const reads = source.readJson('reads.json') || { reads: {} };
  const friendMeta = source.readJson('friendmeta.json') || { byOwner: {} };
  const messagesDir = path.join(source.root, 'messages');
  const messageFiles = fs.existsSync(messagesDir)
    ? fs.readdirSync(messagesDir).filter((name) => name.endsWith('.jsonl')).sort()
    : [];

  const diffs = layout.failures.map((row) => ({
    kind: 'physical-layout',
    id: row.path || row.id || String(row.shardId == null ? '' : row.shardId),
    code: row.code
  }));
  let checked = 0;
  const compare = (kind, id, legacy, shadow) => {
    checked += 1;
    if (stable(legacy) !== stable(shadow)) {
      diffs.push({ kind, id, legacyHash: digest(legacy), shadowHash: digest(shadow) });
    }
  };

  for (const user of users) compare('user', user.id, user, physical.readUser(user.id));
  for (const chat of chats) compare('chat', chat.id, chat, physical.readChat(chat.id));
  for (const moment of moments) compare('moment', moment.id, moment, physical.readMoment(moment.id));
  for (const [userId, byChat] of Object.entries(reads.reads || {})) {
    for (const [chatId, value] of Object.entries(byChat || {})) {
      compare('read', chatId + '|' + userId, value,
        physical.readReadCursor(userId, chatId));
    }
  }
  for (const [ownerId, byFriend] of Object.entries(friendMeta.byOwner || {})) {
    for (const [friendId, value] of Object.entries(byFriend || {})) {
      compare('friendMeta', ownerId + '|' + friendId, value,
        physical.readFriendMeta(ownerId, friendId));
    }
  }
  for (const name of messageFiles) {
    const chatId = name.slice(0, -'.jsonl'.length);
    compare('messages', chatId, source.messageHash(chatId), physical.messageHash(chatId));
  }

  const sourceUserIds = new Set(users.map((row) => row.id));
  const sourceChatIds = new Set(chats.map((row) => row.id));
  const sourceMomentIds = new Set(moments.map((row) => row.id));
  const physicalUserIds = [];
  const physicalChatIds = [];
  const physicalMomentIds = [];
  for (let shard = 0; shard < physical.shardCount; shard += 1) {
    physicalUserIds.push(...rowsOf(
      physical.readShardJson(shard, 'users.json'), 'users'
    ).map((row) => row.id));
    physicalChatIds.push(...rowsOf(
      physical.readShardJson(shard, 'chats.json'), 'chats'
    ).map((row) => row.id));
    physicalMomentIds.push(...rowsOf(
      physical.readShardJson(shard, 'moments.json'), 'moments'
    ).map((row) => row.id));
  }
  for (const [kind, ids, sourceIds] of [
    ['user', physicalUserIds, sourceUserIds],
    ['chat', physicalChatIds, sourceChatIds],
    ['moment', physicalMomentIds, sourceMomentIds]
  ]) {
    const seen = new Set();
    for (const id of ids) {
      if (seen.has(id)) diffs.push({ kind: kind + '-duplicate', id });
      seen.add(id);
      if (!sourceIds.has(id)) diffs.push({ kind: kind + '-extra', id });
    }
  }

  const deterministic = {
    version: 1,
    topologyId: physical.routePlan.topologyId,
    routePlanHash: physical.routePlan.hash,
    physicalLayoutHash: layout.hash,
    physicalLayoutOk: layout.ok,
    checked: {
      users: users.length,
      chats: chats.length,
      moments: moments.length,
      reads: Object.values(reads.reads || {}).reduce(
        (sum, row) => sum + Object.keys(row || {}).length, 0
      ),
      friendMeta: Object.values(friendMeta.byOwner || {}).reduce(
        (sum, row) => sum + Object.keys(row || {}).length, 0
      ),
      messages: messageFiles.length
    },
    diffHash: digest(diffs)
  };
  return Object.assign({
    readOnly: true,
    ok: diffs.length === 0,
    sourceDir: source.root,
    physicalRoot: physical.root,
    checked,
    diffs: diffs.slice(0, 1000),
    fingerprint: digest(deterministic)
  }, deterministic);
}

module.exports = {
  PhysicalShardReader,
  LegacyDataReader,
  runShadowReadAudit
};
