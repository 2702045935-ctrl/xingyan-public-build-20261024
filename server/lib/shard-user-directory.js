'use strict';

const crypto = require('crypto');
const { resolveRoute } = require('./shard-route-plan');

function canonical(value) {
  if (value === null || typeof value !== 'object') {
    return JSON.stringify(value === undefined ? null : value);
  }
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  return '{' + Object.keys(value).sort().map((key) =>
    JSON.stringify(key) + ':' + canonical(value[key])
  ).join(',') + '}';
}

function hash(value) {
  return crypto.createHash('sha256').update(canonical(value)).digest('hex');
}

function normalizeUsername(value) {
  return String(value || '').trim().toLowerCase();
}

function normalizePhone(value) {
  const digits = String(value || '').replace(/\D/g, '');
  return /^86\d{11}$/.test(digits) ? digits.slice(2) : digits;
}

function normalizeEmail(value) {
  return String(value || '').trim().toLowerCase();
}

function buildUserDirectory(options) {
  const opts = options || {};
  const users = Array.isArray(opts.users) ? opts.users : [];
  const routePlan = opts.routePlan;
  const shardCount = Math.floor(Number(routePlan && routePlan.shardCount));
  if (!Number.isInteger(shardCount) || shardCount < 1) {
    throw new Error('route plan shardCount is invalid');
  }
  const seenUsers = new Set();
  const aliases = new Map();
  const entries = [];
  const byShard = Array.from({ length: shardCount }, () => 0);
  const addAlias = (kind, value, id) => {
    if (!value) return;
    const key = kind + ':' + value;
    const current = aliases.get(key);
    if (current && current !== id) {
      throw new Error('duplicate ' + kind + ' directory alias: ' + value);
    }
    aliases.set(key, id);
  };
  for (const user of users) {
    const id = String(user && user.id || '');
    if (!id) throw new Error('user id is required');
    if (seenUsers.has(id)) throw new Error('duplicate user id: ' + id);
    seenUsers.add(id);
    const shard = resolveRoute(routePlan, 'user', id);
    if (!Number.isInteger(shard) || shard < 0 || shard >= shardCount) {
      throw new Error('invalid user owner for ' + id);
    }
    const username = normalizeUsername(user.username);
    const phone = normalizePhone(user.phone);
    const email = normalizeEmail(user.email);
    addAlias('username', username, id);
    addAlias('phone', phone, id);
    addAlias('email', email, id);
    entries.push({ id, shard, username, phone, email });
    byShard[shard] += 1;
  }
  entries.sort((left, right) => left.id.localeCompare(right.id));
  const directory = {
    version: 1,
    kind: 'user-directory',
    topologyId: String(routePlan.topologyId || ''),
    routePlanHash: String(routePlan.hash || ''),
    shardCount,
    ports: Array.isArray(routePlan.ports) ? routePlan.ports.slice() : [],
    userCount: entries.length,
    byShard,
    entries
  };
  directory.hash = hash({
    version: directory.version,
    kind: directory.kind,
    topologyId: directory.topologyId,
    routePlanHash: directory.routePlanHash,
    shardCount: directory.shardCount,
    userCount: directory.userCount,
    byShard: directory.byShard,
    entries: directory.entries
  });
  return directory;
}

function createUserDirectoryResolver(directory) {
  if (!directory || directory.version !== 1 || directory.kind !== 'user-directory'
      || !Array.isArray(directory.entries)) {
    throw new Error('user directory is invalid');
  }
  const byId = new Map();
  const aliases = new Map();
  for (const entry of directory.entries) {
    if (!entry || !entry.id || !Number.isInteger(entry.shard)) {
      throw new Error('user directory entry is invalid');
    }
    if (byId.has(entry.id)) throw new Error('duplicate user directory id: ' + entry.id);
    byId.set(entry.id, entry);
    for (const [kind, value] of Object.entries({
      username: entry.username,
      phone: entry.phone,
      email: entry.email
    })) {
      if (!value) continue;
      const key = kind + ':' + value;
      if (aliases.has(key) && aliases.get(key).id !== entry.id) {
        throw new Error('duplicate user directory alias: ' + value);
      }
      aliases.set(key, entry);
    }
  }
  return {
    byId(id) {
      return byId.get(String(id || '')) || null;
    },
    byUsername(value) {
      return aliases.get('username:' + normalizeUsername(value)) || null;
    },
    byPhone(value) {
      return aliases.get('phone:' + normalizePhone(value)) || null;
    },
    byEmail(value) {
      return aliases.get('email:' + normalizeEmail(value)) || null;
    }
  };
}

function verifyUserDirectory(directory, options) {
  const opts = options || {};
  const failures = [];
  let resolver;
  try {
    resolver = createUserDirectoryResolver(directory);
  } catch (error) {
    failures.push({ code: 'directory-invalid', message: error.message });
    return { ok: false, failures };
  }
  const routePlan = opts.routePlan;
  if (routePlan && directory.routePlanHash !== routePlan.hash) {
    failures.push({ code: 'route-plan-hash', expected: routePlan.hash, actual: directory.routePlanHash });
  }
  for (const user of opts.users || []) {
    const id = String(user && user.id || '');
    const entry = resolver.byId(id);
    if (!entry) {
      failures.push({ code: 'user-missing', id });
      continue;
    }
    const owner = routePlan ? resolveRoute(routePlan, 'user', id) : entry.shard;
    if (entry.shard !== owner) failures.push({ code: 'user-owner', id, expected: owner, actual: entry.shard });
  }
  return {
    ok: failures.length === 0,
    hash: directory.hash,
    userCount: directory.userCount,
    byShard: directory.byShard,
    failures: failures.slice(0, 500)
  };
}

module.exports = {
  buildUserDirectory,
  createUserDirectoryResolver,
  verifyUserDirectory,
  normalizeUsername,
  normalizePhone,
  normalizeEmail
};
