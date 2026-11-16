'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { canonical, hash } = require('./shard-snapshot');
const { ownerFor } = require('./shard-placement-plan');
const { pairKey } = require('./shard-domain');

function readJson(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch (_) { return fallback; }
}

function rowsOf(value, key) {
  if (Array.isArray(value)) return value;
  return value && Array.isArray(value[key]) ? value[key] : [];
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temporary = file + '.' + process.pid + '.tmp';
  fs.writeFileSync(temporary, JSON.stringify(value, null, 2), 'utf8');
  fs.renameSync(temporary, file);
}

function fileHash(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function stableRows(rows, idOf) {
  return (rows || []).slice().sort((left, right) => {
    const leftId = String(idOf(left) || '');
    const rightId = String(idOf(right) || '');
    return leftId.localeCompare(rightId)
      || canonical(left).localeCompare(canonical(right));
  });
}

function assertEmptyTarget(target, label) {
  if (!fs.existsSync(target)) return;
  if (fs.readdirSync(target).length) {
    throw new Error(label + ' must be empty or absent');
  }
}

function rehearseShardPlacement(options) {
  const opts = options || {};
  const sourceDir = path.resolve(String(opts.sourceDir || ''));
  const stageDir = path.resolve(String(opts.stageDir || ''));
  const rehydrateDir = path.resolve(String(opts.rehydrateDir || ''));
  const routePlan = opts.routePlan;
  const shardCount = Number(routePlan && routePlan.shardCount);
  if (!sourceDir || !stageDir || !rehydrateDir || !Number.isInteger(shardCount)) {
    throw new Error('sourceDir, stageDir, rehydrateDir and routePlan are required');
  }
  if (stageDir === sourceDir || rehydrateDir === sourceDir) {
    throw new Error('rehearsal targets must differ from source');
  }
  assertEmptyTarget(stageDir, 'stageDir');
  assertEmptyTarget(rehydrateDir, 'rehydrateDir');

  const users = rowsOf(readJson(path.join(sourceDir, 'users.json'), { users: [] }), 'users');
  const friendships = rowsOf(
    readJson(path.join(sourceDir, 'friendships.json'), { friendships: [] }),
    'friendships'
  );
  const chats = rowsOf(readJson(path.join(sourceDir, 'chats.json'), { chats: [] }), 'chats');
  const reads = readJson(path.join(sourceDir, 'reads.json'), { reads: {} }).reads || {};
  const friendMeta = readJson(path.join(sourceDir, 'friendmeta.json'), { byOwner: {} }).byOwner || {};
  const moments = rowsOf(readJson(path.join(sourceDir, 'moments.json'), { moments: [] }), 'moments');
  const notices = rowsOf(
    readJson(path.join(sourceDir, 'moment-notices.json'), { items: [] }),
    'items'
  );
  const messagesDir = path.join(sourceDir, 'messages');
  const allThreads = fs.existsSync(messagesDir)
    ? fs.readdirSync(messagesDir).filter((name) => name.endsWith('.jsonl')).sort()
    : [];
  const threadLimit = Math.max(0, Number(opts.threadLimit) || allThreads.length);
  const threads = allThreads.slice(0, threadLimit);
  const includedChatIds = new Set(threads.map((name) => name.slice(0, -'.jsonl'.length)));

  const shardData = Array.from({ length: shardCount }, () => ({
    users: [],
    friendships: [],
    chats: [],
    reads: {},
    friendMeta: {},
    moments: [],
    momentNotices: []
  }));
  const put = (entityType, routeEntityType, routeId, shard, apply) => {
    const owner = ownerFor(routePlan, shardCount, routeEntityType, routeId);
    if (!Number.isInteger(owner) || owner < 0 || owner >= shardCount) {
      throw new Error('invalid owner for ' + entityType + ':' + routeId);
    }
    apply(shardData[owner], owner);
  };
  for (const user of users) {
    put('user', 'user', user.id, null, (target) => target.users.push(user));
  }
  for (const friendship of friendships) {
    const routeId = pairKey(friendship.fromId, friendship.toId);
    put('friendship', 'friendship', routeId, null, (target) => target.friendships.push(friendship));
  }
  for (const chat of chats) {
    put('chat', 'chat', chat.id, null, (target) => target.chats.push(chat));
  }
  for (const [ownerId, byChat] of Object.entries(reads)) {
    for (const [chatId, seq] of Object.entries(byChat || {})) {
      put('read', 'snapshot_reads', chatId + '|' + ownerId, null, (target) => {
        if (!target.reads[ownerId]) target.reads[ownerId] = {};
        target.reads[ownerId][chatId] = seq;
      });
    }
  }
  for (const [ownerId, byFriend] of Object.entries(friendMeta)) {
    for (const [friendId, value] of Object.entries(byFriend || {})) {
      put('friend_meta', 'snapshot_friendMeta', ownerId + '|' + friendId, null, (target) => {
        if (!target.friendMeta[ownerId]) target.friendMeta[ownerId] = {};
        target.friendMeta[ownerId][friendId] = value;
      });
    }
  }
  for (const moment of moments) {
    put('moment', 'moment', moment.id, null, (target) => target.moments.push(moment));
  }
  for (const notice of notices) {
    put('moment_notice', 'moment_notice', notice.id, null,
      (target) => target.momentNotices.push(notice));
  }

  for (let shard = 0; shard < shardCount; shard += 1) {
    const dir = path.join(stageDir, 'shards', String(shard));
    const data = shardData[shard];
    writeJson(path.join(dir, 'users.json'), { users: data.users });
    writeJson(path.join(dir, 'friendships.json'), { friendships: data.friendships });
    writeJson(path.join(dir, 'chats.json'), { chats: data.chats });
    writeJson(path.join(dir, 'reads.json'), { reads: data.reads, cleared: {} });
    writeJson(path.join(dir, 'friendmeta.json'), { byOwner: data.friendMeta });
    writeJson(path.join(dir, 'moments.json'), { moments: data.moments });
    writeJson(path.join(dir, 'moment-notices.json'), { items: data.momentNotices, seen: {} });
  }

  const messageHashes = {};
  for (const name of threads) {
    const chatId = name.slice(0, -'.jsonl'.length);
    const owner = ownerFor(routePlan, shardCount, 'chat', chatId);
    const target = path.join(stageDir, 'shards', String(owner), 'messages', name);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.copyFileSync(path.join(messagesDir, name), target);
    messageHashes[name] = {
      owner,
      sha256: fileHash(path.join(messagesDir, name))
    };
  }

  const rebuilt = {
    users: [],
    friendships: [],
    chats: [],
    reads: {},
    friendMeta: {},
    moments: [],
    momentNotices: []
  };
  for (let shard = 0; shard < shardCount; shard += 1) {
    const dir = path.join(stageDir, 'shards', String(shard));
    rebuilt.users.push(...rowsOf(readJson(path.join(dir, 'users.json'), { users: [] }), 'users'));
    rebuilt.friendships.push(...rowsOf(
      readJson(path.join(dir, 'friendships.json'), { friendships: [] }), 'friendships'));
    rebuilt.chats.push(...rowsOf(readJson(path.join(dir, 'chats.json'), { chats: [] }), 'chats'));
    rebuilt.moments.push(...rowsOf(
      readJson(path.join(dir, 'moments.json'), { moments: [] }), 'moments'));
    rebuilt.momentNotices.push(...rowsOf(
      readJson(path.join(dir, 'moment-notices.json'), { items: [] }), 'items'));
    const shardReads = readJson(path.join(dir, 'reads.json'), { reads: {} }).reads || {};
    for (const [ownerId, byChat] of Object.entries(shardReads)) {
      if (!rebuilt.reads[ownerId]) rebuilt.reads[ownerId] = {};
      Object.assign(rebuilt.reads[ownerId], byChat);
    }
    const shardMeta = readJson(path.join(dir, 'friendmeta.json'), { byOwner: {} }).byOwner || {};
    for (const [ownerId, byFriend] of Object.entries(shardMeta)) {
      if (!rebuilt.friendMeta[ownerId]) rebuilt.friendMeta[ownerId] = {};
      Object.assign(rebuilt.friendMeta[ownerId], byFriend);
    }
    const shardMessages = path.join(dir, 'messages');
    if (fs.existsSync(shardMessages)) {
      for (const name of fs.readdirSync(shardMessages).filter((entry) => entry.endsWith('.jsonl'))) {
        const target = path.join(rehydrateDir, 'messages', name);
        fs.mkdirSync(path.dirname(target), { recursive: true });
        fs.copyFileSync(path.join(shardMessages, name), target);
      }
    }
  }
  writeJson(path.join(rehydrateDir, 'users.json'), { users: rebuilt.users });
  writeJson(path.join(rehydrateDir, 'friendships.json'), { friendships: rebuilt.friendships });
  writeJson(path.join(rehydrateDir, 'chats.json'), { chats: rebuilt.chats });
  writeJson(path.join(rehydrateDir, 'reads.json'), { reads: rebuilt.reads, cleared: {} });
  writeJson(path.join(rehydrateDir, 'friendmeta.json'), { byOwner: rebuilt.friendMeta });
  writeJson(path.join(rehydrateDir, 'moments.json'), { moments: rebuilt.moments });
  writeJson(path.join(rehydrateDir, 'moment-notices.json'), {
    items: rebuilt.momentNotices,
    seen: {}
  });

  const checks = {
    users: hash(stableRows(users, (row) => row.id)) === hash(stableRows(rebuilt.users, (row) => row.id)),
    friendships: hash(stableRows(friendships, (row) => row.id || pairKey(row.fromId, row.toId)))
      === hash(stableRows(rebuilt.friendships, (row) => row.id || pairKey(row.fromId, row.toId))),
    chats: hash(stableRows(chats, (row) => row.id)) === hash(stableRows(rebuilt.chats, (row) => row.id)),
    reads: hash(reads) === hash(rebuilt.reads),
    friendMeta: hash(friendMeta) === hash(rebuilt.friendMeta),
    moments: hash(stableRows(moments, (row) => row.id))
      === hash(stableRows(rebuilt.moments, (row) => row.id)),
    momentNotices: hash(stableRows(notices, (row) => row.id))
      === hash(stableRows(rebuilt.momentNotices, (row) => row.id))
  };
  for (const [name, expected] of Object.entries(messageHashes)) {
    const file = path.join(rehydrateDir, 'messages', name);
    checks['message:' + name] = fs.existsSync(file) && fileHash(file) === expected.sha256;
  }
  return {
    version: 1,
    ok: Object.values(checks).every(Boolean),
    sourceDir,
    stageDir,
    rehydrateDir,
    shardCount,
    counts: {
      users: users.length,
      friendships: friendships.length,
      chats: chats.length,
      reads: Object.values(reads).reduce((sum, row) => sum + Object.keys(row || {}).length, 0),
      moments: moments.length,
      momentNotices: notices.length,
      messageThreads: threads.length
    },
    messageHashes,
    checks,
    failures: Object.keys(checks).filter((name) => !checks[name])
  };
}

module.exports = { rehearseShardPlacement };
