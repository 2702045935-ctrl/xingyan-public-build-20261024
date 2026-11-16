'use strict';

const crypto = require('crypto');
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

async function setShard(port, secret, plan, row) {
  const response = await fetch('http://127.0.0.1:' + port + '/__shard/write-freeze', {
    method: 'POST',
    signal: AbortSignal.timeout(3000),
    headers: {
      'Content-Type': 'application/json',
      'X-Shard-Relay': secret
    },
    body: JSON.stringify({
      frozen: row.frozen,
      epoch: row.epoch,
      reason: row.reason || '',
      planHash: plan.hash,
      fileSha256: plan.fileHash
    })
  });
  const payload = await response.json();
  if (!response.ok || !payload || payload.ok !== true
      || payload.data.frozen !== row.frozen
      || payload.data.fenceEpoch !== row.epoch) {
    throw new Error('write freeze switch failed on port ' + port
      + ': ' + (payload && payload.error || response.status));
  }
  return payload.data;
}

async function healthRows(ports) {
  return Promise.all(ports.map((port) => health(port)));
}

async function rollbackOpen(ports, secret, plan) {
  const results = await Promise.allSettled(ports.map(async (port) => {
    const row = await health(port);
    return setShard(port, secret, plan, {
      frozen: false,
      epoch: Number(row.fenceEpoch) + 1,
      reason: ''
    });
  }));
  const failures = results
    .filter((result) => result.status === 'rejected')
    .map((result) => result.reason && result.reason.message || String(result.reason));
  if (failures.length) throw new Error('write freeze rollback failed: ' + failures.join('; '));
}

async function switchWriteFreeze(options) {
  const opts = options || {};
  const ports = Array.from(new Set((opts.ports || []).map(Number)));
  const frozen = opts.frozen === true;
  const secretFile = path.resolve(String(opts.secretFile || ''));
  const planFile = path.resolve(String(opts.planFile || ''));
  if (ports.length !== 7 || ports.some((port) => !Number.isInteger(port) || port <= 0)) {
    throw new Error('exactly seven valid ports are required');
  }
  const secret = fs.readFileSync(secretFile, 'utf8').trim();
  if (!secret) throw new Error('relay secret is empty');
  const plan = JSON.parse(fs.readFileSync(planFile, 'utf8'));
  const fileHash = crypto.createHash('sha256')
    .update(fs.readFileSync(planFile))
    .digest('hex');
  const before = await healthRows(ports);
  const epoch = Math.max(...before.map((row) => Number(row.fenceEpoch) || 0)) + 1;
  for (const row of before) {
    if (row.chatRoutePlanHash !== plan.hash || row.chatRoutePlanFileHash !== fileHash) {
      throw new Error('route plan mismatch before freeze on port ' + row.port);
    }
    if (row.writeFrozen === frozen) {
      throw new Error('write freeze already in target state on port ' + row.port);
    }
    if (Number(row.fenceEpoch) + 1 !== epoch) {
      throw new Error('fence epoch mismatch before freeze on port ' + row.port);
    }
  }
  try {
    const switched = await Promise.all(ports.map((port) => setShard(port, secret, plan, {
      frozen,
      epoch,
      reason: frozen ? String(opts.reason || 'physical-shard-cutover') : ''
    })));
    const after = await healthRows(ports);
    for (const row of after) {
      if (row.writeFrozen !== frozen || row.fenceEpoch !== epoch) {
        throw new Error('write freeze verification failed on port ' + row.port);
      }
    }
    return {
      ok: true,
      frozen,
      fenceEpoch: epoch,
      planHash: plan.hash,
      fileSha256: fileHash,
      ports,
      switched,
      before,
      after
    };
  } catch (error) {
    try { await rollbackOpen(ports, secret, plan); } catch (_) { /* best effort */ }
    throw error;
  }
}

module.exports = { switchWriteFreeze };
