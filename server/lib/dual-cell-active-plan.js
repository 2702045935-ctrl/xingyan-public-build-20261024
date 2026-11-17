'use strict';

const crypto = require('crypto');

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

function text(value, max) {
  return String(value == null ? '' : value).trim().slice(0, max || 500);
}

function normalizeRoot(value) {
  return String(value || '').replace(/\\/g, '/').replace(/\/+$/, '');
}

function pathContains(parent, child) {
  return child === parent || child.startsWith(parent + '/');
}

function baseUrlOf(value) {
  try {
    const url = new URL(String(value || ''));
    if (url.username || url.password) return null;
    return url;
  } catch (_) {
    return null;
  }
}

function sortedUniqueShards(value, shardCount, failures, code) {
  if (!Array.isArray(value)) {
    failures.push({ code });
    return [];
  }
  const rows = value.map(Number);
  if (rows.some((shard) => !Number.isInteger(shard) || shard < 0 || shard >= shardCount)) {
    failures.push({ code });
    return [];
  }
  if (new Set(rows).size !== rows.length) failures.push({ code: code + '-duplicate' });
  return rows.sort((left, right) => left - right);
}

function validateActiveDualCellPlan(plan) {
  const input = plan || {};
  const failures = [];
  const fail = (code, details) => failures.push(Object.assign({ code }, details || {}));
  if (Number(input.version) !== 1) fail('version', { expected: 1, actual: input.version });
  if (text(input.mode, 30) !== 'active-active') {
    fail('mode', { expected: 'active-active', actual: input.mode });
  }
  const topologyId = text(input.topologyId, 120);
  if (!topologyId) fail('topology-id');
  const routePlanHash = text(input.routePlanHash, 64).toLowerCase();
  if (!/^[a-f0-9]{64}$/.test(routePlanHash)) fail('route-plan-hash');
  const shardCount = Number(input.shardCount);
  if (!Number.isInteger(shardCount) || shardCount < 2 || shardCount > 64) {
    fail('shard-count', { value: input.shardCount });
  }

  const activation = input.activation || {};
  const trafficMode = text(activation.trafficMode, 20);
  const canaryPercent = Number(activation.canaryPercent);
  if (!['dormant', 'canary', 'active'].includes(trafficMode)) {
    fail('traffic-mode', { value: activation.trafficMode });
  }
  if (!Number.isInteger(canaryPercent) || canaryPercent < 0 || canaryPercent > 100) {
    fail('canary-percent', { value: activation.canaryPercent });
  }
  if (typeof activation.writesEnabled !== 'boolean') fail('writes-enabled');
  if (trafficMode === 'dormant'
      && (activation.writesEnabled !== false || canaryPercent !== 0)) {
    fail('dormant-must-be-write-disabled');
  }
  if (trafficMode === 'active' && canaryPercent !== 100) {
    fail('active-requires-full-canary');
  }

  const cells = input.cells || {};
  const rawCells = [
    ['a', cells.a || {}],
    ['b', cells.b || {}]
  ];
  const normalizedCells = {};
  const owners = Array.from({ length: shardCount }, () => []);
  const ids = new Set();
  const hosts = new Set();
  const domains = new Set();
  const roots = [];
  for (const [key, raw] of rawCells) {
    const id = text(raw.id, 80);
    const host = text(raw.host, 200).toLowerCase();
    const failureDomain = text(raw.failureDomain, 120);
    const dataRoot = normalizeRoot(text(raw.dataRoot, 500));
    const baseUrl = baseUrlOf(raw.baseUrl);
    const role = text(raw.role, 20);
    if (!id) fail('cell-' + key + '-id');
    if (!host) fail('cell-' + key + '-host');
    if (!failureDomain) fail('cell-' + key + '-failure-domain');
    if (!dataRoot) fail('cell-' + key + '-data-root');
    if (!baseUrl) fail('cell-' + key + '-base-url');
    if (role !== 'active') fail('cell-' + key + '-role', { expected: 'active', actual: role });
    if (ids.has(id)) fail('cell-id-duplicate', { id });
    if (hosts.has(host)) fail('cell-host-shared', { host });
    if (domains.has(failureDomain)) {
      fail('failure-domain-shared', { failureDomain });
    }
    ids.add(id);
    hosts.add(host);
    domains.add(failureDomain);
    if (dataRoot) roots.push({ key, root: dataRoot });
    if (baseUrl && baseUrl.hostname.toLowerCase() !== host) {
      fail('cell-' + key + '-base-url-host', { host, urlHost: baseUrl.hostname });
    }
    const local = baseUrl && /^(127\.0\.0\.1|::1|localhost)$/i.test(baseUrl.hostname);
    if (baseUrl && baseUrl.protocol !== 'https:' && !local) {
      fail('cell-' + key + '-insecure-transport', { protocol: baseUrl.protocol });
    }
    const ownedShards = sortedUniqueShards(
      raw.ownedShards,
      shardCount,
      failures,
      'cell-' + key + '-owned-shards'
    );
    for (const shard of ownedShards) owners[shard].push(key);
    normalizedCells[key] = {
      id,
      host,
      role,
      failureDomain,
      dataRoot,
      baseUrl: baseUrl ? baseUrl.toString().replace(/\/+$/, '') : '',
      ownedShards
    };
  }
  if (roots.length === 2
      && (pathContains(roots[0].root, roots[1].root)
        || pathContains(roots[1].root, roots[0].root))) {
    fail('cell-data-root-overlap', { a: roots[0].root, b: roots[1].root });
  }
  for (let shard = 0; shard < shardCount; shard += 1) {
    if (owners[shard].length === 0) fail('shard-unowned', { shard });
    if (owners[shard].length > 1) fail('shard-multi-owner', { shard, cells: owners[shard] });
  }

  const lease = input.lease || {};
  const ttlMs = Number(lease.ttlMs);
  const renewalMs = Number(lease.renewalMs);
  if (text(lease.authority, 40) !== 'external-consensus') {
    fail('lease-authority', { expected: 'external-consensus' });
  }
  if (text(lease.fencing, 20) !== 'epoch') fail('lease-fencing', { expected: 'epoch' });
  if (!Number.isInteger(ttlMs) || ttlMs < 3000 || ttlMs > 120000) {
    fail('lease-ttl', { value: lease.ttlMs });
  }
  if (!Number.isInteger(renewalMs) || renewalMs < 500 || renewalMs >= ttlMs / 2) {
    fail('lease-renewal', { value: lease.renewalMs, max: Math.floor((ttlMs || 0) / 2) - 1 });
  }

  const replication = input.replication || {};
  const batchSize = Number(replication.batchSize);
  const peerTimeoutMs = Number(replication.peerTimeoutMs);
  const criticalTypes = Array.isArray(replication.criticalEntityTypes)
    ? replication.criticalEntityTypes.map((value) => text(value, 80).toLowerCase()).filter(Boolean)
    : [];
  if (text(replication.transport, 20) !== 'https') {
    fail('replication-transport', { expected: 'https' });
  }
  if (text(replication.delivery, 30) !== 'durable-outbox') {
    fail('replication-delivery', { expected: 'durable-outbox' });
  }
  if (text(replication.standardAck, 40) !== 'owner-durable-outbox') {
    fail('standard-ack', { expected: 'owner-durable-outbox' });
  }
  if (text(replication.criticalAck, 40) !== 'peer-durable-outbox') {
    fail('critical-ack', { expected: 'peer-durable-outbox' });
  }
  if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > 5000) {
    fail('replication-batch-size', { value: replication.batchSize });
  }
  if (!Number.isInteger(peerTimeoutMs) || peerTimeoutMs < 200 || peerTimeoutMs > 10000) {
    fail('replication-peer-timeout', { value: replication.peerTimeoutMs });
  }
  if (!criticalTypes.length || new Set(criticalTypes).size !== criticalTypes.length) {
    fail('critical-entity-types');
  }

  const gateway = input.gateway || {};
  if (text(gateway.writeMode, 30) !== 'lease-owner-only') {
    fail('gateway-write-mode', { expected: 'lease-owner-only' });
  }
  if (text(gateway.readMode, 30) !== 'local-replica') {
    fail('gateway-read-mode', { expected: 'local-replica' });
  }
  if (gateway.rejectStaleOwner !== true) fail('gateway-stale-owner-guard');

  const normalized = {
    version: 1,
    mode: text(input.mode, 30),
    topologyId,
    routePlanHash,
    shardCount,
    activation: {
      trafficMode,
      canaryPercent,
      writesEnabled: activation.writesEnabled === true
    },
    cells: normalizedCells,
    lease: {
      authority: text(lease.authority, 40),
      ttlMs,
      renewalMs,
      fencing: text(lease.fencing, 20)
    },
    replication: {
      transport: text(replication.transport, 20),
      delivery: text(replication.delivery, 30),
      standardAck: text(replication.standardAck, 40),
      criticalAck: text(replication.criticalAck, 40),
      criticalEntityTypes: criticalTypes.slice().sort(),
      batchSize,
      peerTimeoutMs
    },
    gateway: {
      writeMode: text(gateway.writeMode, 30),
      readMode: text(gateway.readMode, 30),
      rejectStaleOwner: gateway.rejectStaleOwner === true
    }
  };
  return {
    ok: failures.length === 0,
    failures,
    plan: normalized,
    hash: hash(normalized),
    shardOwners: owners.map((row) => row[0] || '')
  };
}

module.exports = {
  validateActiveDualCellPlan
};
