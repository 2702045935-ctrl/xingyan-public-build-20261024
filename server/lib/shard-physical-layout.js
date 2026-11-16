'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { ownerFor } = require('./shard-placement-plan');
const { verifyRoutePlan } = require('./shard-route-plan');
const { pairKey } = require('./shard-domain');

const REQUIRED_FILES = [
  'users.json',
  'friendships.json',
  'chats.json',
  'reads.json',
  'friendmeta.json',
  'moments.json',
  'moment-notices.json'
];

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function rowsOf(value, key) {
  if (Array.isArray(value)) return value;
  return value && Array.isArray(value[key]) ? value[key] : [];
}

function fileHash(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function stable(value) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return '[' + value.map(stable).join(',') + ']';
  return '{' + Object.keys(value).sort().map((key) =>
    JSON.stringify(key) + ':' + stable(value[key])
  ).join(',') + '}';
}

function verifyPhysicalLayout(options) {
  const opts = options || {};
  const root = path.resolve(String(opts.root || ''));
  const routePlan = opts.routePlan;
  const routeVerification = verifyRoutePlan(routePlan);
  const shardCount = Number(routePlan && routePlan.shardCount);
  if (!root) throw new Error('root is required');
  if (!routeVerification.ok || !Number.isInteger(shardCount) || shardCount < 2) {
    throw new Error('valid route plan is required');
  }

  const failures = [];
  const addFailure = (code, details) => failures.push(Object.assign({ code }, details || {}));
  const rootEntries = fs.readdirSync(root, { withFileTypes: true });
  const allowedRoot = new Set(['shards', 'physical-layout.json']);
  for (const entry of rootEntries) {
    if (!allowedRoot.has(entry.name)) {
      addFailure('shared-root-entry', { path: entry.name });
    }
  }

  const shardsDir = path.join(root, 'shards');
  if (!fs.existsSync(shardsDir) || !fs.statSync(shardsDir).isDirectory()) {
    throw new Error('physical layout has no shards directory');
  }
  const shardEntries = fs.readdirSync(shardsDir, { withFileTypes: true });
  const expectedNames = new Set(Array.from({ length: shardCount }, (_, id) => String(id)));
  for (const entry of shardEntries) {
    if (!expectedNames.has(entry.name) || !entry.isDirectory()) {
      addFailure('unexpected-shard-entry', { path: entry.name });
    }
  }

  const userOwners = new Map();
  const friendshipOwners = new Map();
  const chatOwners = new Map();
  const readOwners = new Map();
  const friendMetaOwners = new Map();
  const momentOwners = new Map();
  const momentNoticeOwners = new Map();
  const byShard = Array.from({ length: shardCount }, (_, id) => ({
    id,
    users: 0,
    friendships: 0,
    chats: 0,
    reads: 0,
    friendMeta: 0,
    moments: 0,
    momentNotices: 0,
    messages: 0
  }));
  const contentDigest = [];

  function noteOwner(map, id, shard, kind) {
    if (!id) return;
    const owners = map.get(id) || [];
    if (owners.indexOf(shard) < 0) owners.push(shard);
    map.set(id, owners);
  }

  function scanTree(directory, prefix) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const rel = prefix ? prefix + '/' + entry.name : entry.name;
      const full = path.join(directory, entry.name);
      const stat = fs.lstatSync(full);
      if (stat.isSymbolicLink()) {
        addFailure('symbolic-link', { path: rel });
      } else if (stat.isDirectory()) {
        scanTree(full, rel);
      }
    }
  }

  for (let shardId = 0; shardId < shardCount; shardId += 1) {
    const shardDir = path.join(shardsDir, String(shardId));
    if (!fs.existsSync(shardDir) || !fs.statSync(shardDir).isDirectory()) {
      addFailure('missing-shard-directory', { shardId });
      continue;
    }
    const allowedFiles = new Set(REQUIRED_FILES);
    for (const entry of fs.readdirSync(shardDir, { withFileTypes: true })) {
      const allowed = entry.isDirectory()
        ? entry.name === 'messages'
        : entry.isFile() && allowedFiles.has(entry.name);
      if (!allowed) {
        addFailure('unexpected-shard-entry', { shardId, path: entry.name });
      }
    }
    scanTree(shardDir, String(shardId));
    for (const name of REQUIRED_FILES) {
      const file = path.join(shardDir, name);
      if (!fs.existsSync(file) || !fs.statSync(file).isFile()) {
        addFailure('missing-authority-file', { shardId, file: name });
      }
    }
    const messagesDir = path.join(shardDir, 'messages');
    if (!fs.existsSync(messagesDir) || !fs.statSync(messagesDir).isDirectory()) {
      addFailure('missing-messages-directory', { shardId });
    }

    const users = rowsOf(readJson(path.join(shardDir, 'users.json')), 'users');
    const friendships = rowsOf(readJson(path.join(shardDir, 'friendships.json')), 'friendships');
    const chats = rowsOf(readJson(path.join(shardDir, 'chats.json')), 'chats');
    const reads = readJson(path.join(shardDir, 'reads.json')).reads || {};
    const friendMeta = readJson(path.join(shardDir, 'friendmeta.json')).byOwner || {};
    const moments = rowsOf(readJson(path.join(shardDir, 'moments.json')), 'moments');
    const notices = rowsOf(readJson(path.join(shardDir, 'moment-notices.json')), 'items');
    byShard[shardId].users = users.length;
    byShard[shardId].friendships = friendships.length;
    byShard[shardId].chats = chats.length;
    byShard[shardId].moments = moments.length;
    byShard[shardId].momentNotices = notices.length;

    for (const user of users) {
      noteOwner(userOwners, user.id, shardId, 'user');
    }
    for (const friendship of friendships) {
      noteOwner(friendshipOwners,
        pairKey(friendship.fromId, friendship.toId), shardId, 'friendship');
    }
    for (const chat of chats) {
      noteOwner(chatOwners, chat.id, shardId, 'chat');
    }
    for (const [ownerId, byChat] of Object.entries(reads)) {
      for (const chatId of Object.keys(byChat || {})) {
        noteOwner(readOwners, chatId + '|' + ownerId, shardId, 'snapshot_reads');
        byShard[shardId].reads += 1;
      }
    }
    for (const [ownerId, byFriend] of Object.entries(friendMeta)) {
      for (const friendId of Object.keys(byFriend || {})) {
        noteOwner(friendMetaOwners, ownerId + '|' + friendId, shardId, 'snapshot_friendMeta');
        byShard[shardId].friendMeta += 1;
      }
    }
    for (const moment of moments) {
      noteOwner(momentOwners, moment.id, shardId, 'moment');
    }
    for (const notice of notices) {
      noteOwner(momentNoticeOwners, notice.id, shardId, 'moment_notice');
    }
    contentDigest.push({
      shardId,
      usersFile: fileHash(path.join(shardDir, 'users.json')),
      friendshipsFile: fileHash(path.join(shardDir, 'friendships.json')),
      chatsFile: fileHash(path.join(shardDir, 'chats.json')),
      readsFile: fileHash(path.join(shardDir, 'reads.json')),
      friendMetaFile: fileHash(path.join(shardDir, 'friendmeta.json')),
      momentsFile: fileHash(path.join(shardDir, 'moments.json')),
      noticesFile: fileHash(path.join(shardDir, 'moment-notices.json'))
    });

    if (fs.existsSync(messagesDir)) {
      const messageFiles = fs.readdirSync(messagesDir)
        .filter((name) => name.endsWith('.jsonl'))
        .sort();
      for (const name of fs.readdirSync(messagesDir)) {
        if (!name.endsWith('.jsonl')) {
          addFailure('unexpected-message-entry', { shardId, path: name });
        }
      }
      byShard[shardId].messages = messageFiles.length;
      for (const name of messageFiles) {
        const chatId = name.slice(0, -'.jsonl'.length);
        const expected = ownerFor(routePlan, shardCount, 'chat', chatId);
        if (expected !== shardId) {
          addFailure('message-wrong-owner', { shardId, chatId, expected });
        }
        contentDigest.push({
          shardId,
          message: name,
          hash: fileHash(path.join(messagesDir, name))
        });
      }
    }
  }

  const ownerChecks = [
    ['user', userOwners, routePlan, shardCount],
    ['friendship', friendshipOwners, routePlan, shardCount],
    ['chat', chatOwners, routePlan, shardCount],
    ['snapshot_reads', readOwners, routePlan, shardCount],
    ['snapshot_friendMeta', friendMetaOwners, routePlan, shardCount],
    ['moment', momentOwners, routePlan, shardCount],
    ['moment_notice', momentNoticeOwners, routePlan, shardCount]
  ];
  for (const [kind, owners, plan, count] of ownerChecks) {
    for (const [id, shardIds] of owners) {
      if (shardIds.length !== 1) {
        addFailure('duplicate-authority', { kind, id, shards: shardIds });
        continue;
      }
      const expected = ownerFor(plan, count, kind, id);
      if (shardIds[0] !== expected) {
        addFailure('authority-wrong-owner', {
          kind,
          id,
          expected,
          actual: shardIds[0]
        });
      }
    }
  }

  const deterministic = {
    version: 1,
    topologyId: routePlan.topologyId,
    routePlanHash: routePlan.hash,
    shardCount,
    byShard,
    contentDigest
  };
  return {
    version: 1,
    ok: failures.length === 0,
    root,
    topologyId: routePlan.topologyId,
    routePlanHash: routePlan.hash,
    shardCount,
    counts: {
      users: userOwners.size,
      friendships: friendshipOwners.size,
      chats: chatOwners.size,
      reads: readOwners.size,
      friendMeta: friendMetaOwners.size,
      moments: momentOwners.size,
      momentNotices: momentNoticeOwners.size,
      messages: byShard.reduce((sum, row) => sum + row.messages, 0)
    },
    byShard,
    hash: crypto.createHash('sha256').update(stable(deterministic)).digest('hex'),
    failures: failures.slice(0, 500)
  };
}

module.exports = {
  REQUIRED_FILES,
  verifyPhysicalLayout
};
