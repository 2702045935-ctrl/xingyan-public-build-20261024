'use strict';

const fs = require('fs');
const path = require('path');

async function health(port) {
  const response = await fetch('http://127.0.0.1:' + port + '/api/health', {
    signal: AbortSignal.timeout(3000)
  });
  const payload = await response.json();
  if (!response.ok || !payload || payload.ok !== true) {
    throw new Error('health failed on port ' + port);
  }
  return payload.data;
}

async function setShard(port, secret, plan, enabled) {
  const response = await fetch('http://127.0.0.1:' + port + '/__shard/owner-routing', {
    method: 'POST',
    signal: AbortSignal.timeout(3000),
    headers: {
      'Content-Type': 'application/json',
      'X-Shard-Relay': secret
    },
    body: JSON.stringify({
      enabled,
      planHash: plan.hash,
      fileSha256: plan.fileHash
    })
  });
  const payload = await response.json();
  if (!response.ok || !payload || payload.ok !== true || payload.data.enabled !== enabled) {
    throw new Error('owner routing switch failed on port ' + port
      + ': ' + (payload && payload.error || response.status));
  }
  return payload.data;
}

async function switchAll(ports, secret, plan, enabled) {
  return Promise.all(ports.map((port) => setShard(port, secret, plan, enabled)));
}

async function switchOwnerRouting(options) {
  const opts = options || {};
  const ports = Array.from(new Set((opts.ports || []).map(Number)));
  const enable = opts.enable === true;
  const secretFile = path.resolve(String(opts.secretFile || ''));
  const planFile = path.resolve(String(opts.planFile || ''));
  if (ports.length !== 7 || ports.some((port) => !Number.isInteger(port) || port <= 0)) {
    throw new Error('exactly seven valid ports are required');
  }
  if (new Set(ports).size !== 7) throw new Error('ports must be unique');
  const secret = fs.readFileSync(secretFile, 'utf8').trim();
  if (!secret) throw new Error('relay secret is empty');
  const plan = JSON.parse(fs.readFileSync(planFile, 'utf8'));
  const fileHash = require('crypto').createHash('sha256')
    .update(fs.readFileSync(planFile))
    .digest('hex');
  const before = await Promise.all(ports.map(health));
  for (const row of before) {
    if (row.chatRoutePlanHash !== plan.hash || row.chatRoutePlanFileHash !== fileHash) {
      throw new Error('route plan mismatch before switch on port ' + row.port);
    }
    if (row.chatRoutePlanEnforced === enable) {
      throw new Error('owner routing already in target state on port ' + row.port);
    }
  }
  let switched = [];
  try {
    switched = await switchAll(ports, secret, { hash: plan.hash, fileHash }, enable);
    const after = await Promise.all(ports.map(health));
    for (const row of after) {
      if (row.chatRoutePlanEnforced !== enable) {
        throw new Error('owner routing verification failed on port ' + row.port);
      }
    }
    return {
      ok: true,
      enabled: enable,
      planHash: plan.hash,
      fileSha256: fileHash,
      ports,
      switched,
      before,
      after
    };
  } catch (error) {
    try {
      await switchAll(ports, secret, { hash: plan.hash, fileHash }, false);
    } catch (_) { /* best effort */ }
    throw error;
  }
}

module.exports = {
  switchOwnerRouting
};
