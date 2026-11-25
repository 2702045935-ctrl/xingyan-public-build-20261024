'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const FORMAT_VERSION = 1;
const DEFAULT_SHARD_SIZE = 1000;
const MAX_SHARD_SIZE = 5000;
const MAX_MEMBERS = 10000;

function digest(value) {
  return crypto.createHash('sha256').update(String(value)).digest('hex');
}

function safeChatSegment(chatId) {
  const raw = String(chatId || '').trim();
  if (!raw) throw new Error('chatId is required');
  return crypto.createHash('sha256').update(raw).digest('hex');
}

function generationId() {
  return Date.now().toString(36) + '-' + crypto.randomBytes(8).toString('hex');
}

function normalizeMembers(members) {
  if (!Array.isArray(members)) throw new Error('members must be an array');
  const unique = new Set();
  for (const value of members) {
    const member = String(value == null ? '' : value).trim();
    if (!member) continue;
    if (member.length > 160) throw new Error('member id is too long');
    unique.add(member);
  }
  return Array.from(unique).sort();
}

function atomicJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temporary = file + '.' + process.pid + '.'
    + crypto.randomBytes(6).toString('hex') + '.tmp';
  const fd = fs.openSync(temporary, 'w');
  try {
    fs.writeFileSync(fd, JSON.stringify(value) + '\n', 'utf8');
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.renameSync(temporary, file);
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

class GroupMembershipDirectory {
  constructor(options) {
    const opts = options || {};
    this.root = path.resolve(String(opts.root || ''));
    if (!this.root || opts.root == null) {
      throw new Error('group membership root is required');
    }
    this.shardSize = Math.max(
      100,
      Math.min(MAX_SHARD_SIZE, Number(opts.shardSize) || DEFAULT_SHARD_SIZE)
    );
    this.maxMembers = Math.max(
      2,
      Math.min(MAX_MEMBERS, Number(opts.maxMembers) || MAX_MEMBERS)
    );
    this.onShardRead = typeof opts.onShardRead === 'function'
      ? opts.onShardRead
      : null;
    fs.mkdirSync(this.root, { recursive: true });
  }

  groupDir(chatId) {
    const key = safeChatSegment(chatId);
    return path.join(this.root, 'groups', key.slice(0, 2), key);
  }

  currentFile(chatId) {
    return path.join(this.groupDir(chatId), 'current.json');
  }

  generationDir(chatId, generation) {
    if (!/^[A-Za-z0-9._-]+$/.test(String(generation || ''))) {
      throw new Error('generation is invalid');
    }
    return path.join(this.groupDir(chatId), 'generations', generation);
  }

  install(chatId, members, options) {
    const opts = options || {};
    const normalized = normalizeMembers(members);
    if (!normalized.length) throw new Error('group must have at least one member');
    if (normalized.length > this.maxMembers) {
      throw new Error('group exceeds membership limit');
    }
    const shardSize = Math.max(
      100,
      Math.min(MAX_SHARD_SIZE, Number(opts.shardSize) || this.shardSize)
    );
    const generation = generationId();
    const target = this.generationDir(chatId, generation);
    fs.mkdirSync(target, { recursive: true });

    const shards = [];
    for (let start = 0, index = 0; start < normalized.length;
      start += shardSize, index += 1) {
      const rows = normalized.slice(start, start + shardSize);
      const file = 'members-' + String(index).padStart(5, '0') + '.json';
      const body = JSON.stringify(rows) + '\n';
      atomicJson(path.join(target, file), rows);
      shards.push({
        index,
        file,
        first: rows[0],
        last: rows[rows.length - 1],
        count: rows.length,
        sha256: digest(body)
      });
    }

    const manifest = {
      version: FORMAT_VERSION,
      chatId: String(chatId),
      generation,
      memberCount: normalized.length,
      shardSize,
      shardCount: shards.length,
      memberDigest: digest(normalized.join('\u0000')),
      shards
    };
    atomicJson(path.join(target, 'manifest.json'), manifest);
    atomicJson(this.currentFile(chatId), {
      version: FORMAT_VERSION,
      chatId: String(chatId),
      generation,
      memberCount: normalized.length,
      manifest: 'generations/' + generation + '/manifest.json'
    });
    this.cleanupGenerations(chatId, generation, 1);
    return manifest;
  }

  manifest(chatId) {
    const current = readJson(this.currentFile(chatId));
    if (!current || Number(current.version) !== FORMAT_VERSION
        || String(current.chatId) !== String(chatId)) {
      throw new Error('group membership pointer is invalid');
    }
    const manifest = readJson(path.join(this.groupDir(chatId), current.manifest));
    if (!manifest || Number(manifest.version) !== FORMAT_VERSION
        || String(manifest.chatId) !== String(chatId)
        || String(manifest.generation) !== String(current.generation)
        || Number(manifest.memberCount) !== Number(current.memberCount)
        || !Array.isArray(manifest.shards)) {
      throw new Error('group membership manifest is invalid');
    }
    return manifest;
  }

  count(chatId) {
    return Number(readJson(this.currentFile(chatId)).memberCount) || 0;
  }

  readShard(chatId, manifest, index) {
    if (!Number.isInteger(index) || index < 0 || index >= manifest.shards.length) {
      throw new Error('group membership shard is out of range');
    }
    const shard = manifest.shards[index];
    const file = path.join(
      this.generationDir(chatId, manifest.generation),
      shard.file
    );
    if (this.onShardRead) this.onShardRead(String(chatId), index);
    const text = fs.readFileSync(file, 'utf8');
    if (digest(text) !== shard.sha256) {
      throw new Error('group membership shard checksum mismatch');
    }
    const rows = JSON.parse(text);
    if (!Array.isArray(rows) || rows.length !== Number(shard.count)
        || rows[0] !== shard.first || rows[rows.length - 1] !== shard.last) {
      throw new Error('group membership shard is invalid');
    }
    return rows;
  }

  page(chatId, cursor, limit) {
    const manifest = this.manifest(chatId);
    const start = Math.max(0, Math.min(manifest.memberCount, Number(cursor) || 0));
    const take = Math.max(1, Math.min(1000, Number(limit) || 100));
    const members = [];
    let position = start;
    while (members.length < take && position < manifest.memberCount) {
      const shardIndex = Math.floor(position / manifest.shardSize);
      const offset = position % manifest.shardSize;
      const shard = this.readShard(chatId, manifest, shardIndex);
      const consumed = Math.min(shard.length - offset, take - members.length);
      members.push(...shard.slice(offset, offset + consumed));
      position += consumed;
    }
    return {
      members,
      nextCursor: position,
      hasMore: position < manifest.memberCount,
      memberCount: manifest.memberCount,
      generation: manifest.generation
    };
  }

  contains(chatId, userId) {
    const manifest = this.manifest(chatId);
    const wanted = String(userId || '');
    if (!wanted) return false;
    let low = 0;
    let high = manifest.shards.length - 1;
    while (low <= high) {
      const middle = (low + high) >> 1;
      const range = manifest.shards[middle];
      if (wanted < range.first) high = middle - 1;
      else if (wanted > range.last) low = middle + 1;
      else return this.readShard(chatId, manifest, middle).includes(wanted);
    }
    return false;
  }

  all(chatId) {
    const manifest = this.manifest(chatId);
    const rows = [];
    for (let index = 0; index < manifest.shardCount; index += 1) {
      rows.push(...this.readShard(chatId, manifest, index));
    }
    if (rows.length !== manifest.memberCount
        || digest(rows.join('\u0000')) !== manifest.memberDigest) {
      throw new Error('group membership generation is incomplete');
    }
    return rows;
  }

  remove(chatId) {
    const dir = this.groupDir(chatId);
    fs.rmSync(dir, { recursive: true, force: true });
  }

  cleanupGenerations(chatId, keepGeneration, keepCount) {
    const dir = path.join(this.groupDir(chatId), 'generations');
    let names = [];
    try { names = fs.readdirSync(dir); } catch (_) { return; }
    const keep = new Set([String(keepGeneration)]);
    const candidates = names.filter((name) => !keep.has(name))
      .map((name) => {
        const full = path.join(dir, name);
        let mtime = 0;
        try { mtime = fs.statSync(full).mtimeMs; } catch (_) {}
        return { full, mtime };
      })
      .sort((left, right) => right.mtime - left.mtime);
    for (const row of candidates.slice(Math.max(0, keepCount - 1))) {
      fs.rmSync(row.full, { recursive: true, force: true });
    }
  }
}

module.exports = {
  GroupMembershipDirectory,
  FORMAT_VERSION,
  DEFAULT_SHARD_SIZE,
  MAX_SHARD_SIZE,
  MAX_MEMBERS
};
