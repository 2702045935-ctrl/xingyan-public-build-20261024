'use strict';

const fs = require('fs');
const path = require('path');

function resolveDirectoryEntry(directory, query) {
  const entries = Array.isArray(directory && directory.entries) ? directory.entries : [];
  const id = String(query && query.id || '');
  if (id) return entries.find((entry) => entry.id === id) || null;
  const username = String(query && query.username || '').trim().toLowerCase();
  if (username) return entries.find((entry) => entry.username === username) || null;
  const phone = String(query && query.phone || '').replace(/\D/g, '').replace(/^86(?=\d{11}$)/, '');
  if (phone) return entries.find((entry) => entry.phone === phone) || null;
  const email = String(query && query.email || '').trim().toLowerCase();
  if (email) return entries.find((entry) => entry.email === email) || null;
  return null;
}

async function lookupUserFromOwner(options) {
  const opts = options || {};
  const directory = opts.directory;
  const plan = opts.routePlan;
  if (!directory || directory.kind !== 'user-directory') {
    throw new Error('user directory is invalid');
  }
  if (!plan || directory.routePlanHash !== plan.hash) {
    throw new Error('route plan does not match user directory');
  }
  const entry = resolveDirectoryEntry(directory, opts.query || {});
  if (!entry) return { ok: false, code: 'USER_NOT_FOUND' };
  const port = Number(plan.ports && plan.ports[entry.shard]);
  if (!Number.isInteger(port) || port <= 0) {
    throw new Error('owner port is invalid for shard ' + entry.shard);
  }
  const response = await fetch('http://127.0.0.1:' + port + '/__shard/user-lookup', {
    method: 'POST',
    signal: AbortSignal.timeout(Number(opts.timeoutMs) || 3000),
    headers: {
      'Content-Type': 'application/json',
      'X-Shard-Relay': String(opts.secret || '')
    },
    body: JSON.stringify({
      userId: entry.id,
      planHash: plan.hash,
      fileSha256: directory.fileSha256 || plan.fileHash
    })
  });
  const payload = await response.json();
  if (!response.ok || !payload || payload.ok !== true) {
    return {
      ok: false,
      code: 'OWNER_LOOKUP_FAILED',
      status: response.status,
      error: payload && payload.error || ''
    };
  }
  const data = payload.data || {};
  if (!data.user || data.user.id !== entry.id || data.owner !== entry.shard) {
    throw new Error('owner lookup returned mismatched user');
  }
  return {
    ok: true,
    entry,
    ownerPort: port,
    user: data.user
  };
}

module.exports = {
  resolveDirectoryEntry,
  lookupUserFromOwner
};
