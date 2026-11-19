'use strict';

const crypto = require('crypto');

const SHA256_RE = /^[a-f0-9]{64}$/i;

function normalizeInts(value) {
  if (!Array.isArray(value)) return [];
  return Array.from(new Set(value.map((item) => Number(item))))
    .filter((item) => Number.isInteger(item))
    .sort((a, b) => a - b);
}

function normalizePorts(value, shardCount) {
  if (!Array.isArray(value) || value.length !== shardCount) return [];
  return value.map((item) => Number(item));
}

function fleetDigest(value) {
  return crypto.createHash('sha256')
    .update(JSON.stringify(value))
    .digest('hex');
}

function validateFleetPlan(input) {
  const plan = input && typeof input === 'object' ? input : {};
  const failures = [];
  const warnings = [];
  const fail = (code, detail) => failures.push({ code, detail: detail || '' });
  const warn = (code, detail) => warnings.push({ code, detail: detail || '' });
  const version = Number(plan.version);
  const shardCount = Number(plan.shardCount);
  const topologyId = String(plan.topologyId || '');
  const routePlanHash = String(plan.routePlanHash || '').toLowerCase();
  const routePlanFileSha256 = String(plan.routePlanFileSha256 || '').toLowerCase();
  const release = plan.release && typeof plan.release === 'object' ? plan.release : {};
  const policy = plan.policy && typeof plan.policy === 'object' ? plan.policy : {};
  const cells = Array.isArray(plan.cells) ? plan.cells : [];

  if (version !== 1) fail('version', 'fleet plan version must be 1');
  if (!topologyId) fail('topology', 'topologyId is required');
  if (!Number.isInteger(shardCount) || shardCount < 1 || shardCount > 128) {
    fail('shard-count', 'shardCount must be between 1 and 128');
  }
  if (!SHA256_RE.test(routePlanHash)) fail('route-plan-hash', 'routePlanHash is invalid');
  if (!SHA256_RE.test(routePlanFileSha256)) {
    fail('route-plan-file-sha256', 'routePlanFileSha256 is invalid');
  }
  if (!String(release.id || '').trim()) fail('release-id', 'release.id is required');
  if (!SHA256_RE.test(String(release.codeSha256 || ''))) {
    fail('release-code-sha256', 'release.codeSha256 is invalid');
  }
  if (policy.maxOwnerShardsInFlight !== 1) {
    fail('owner-concurrency', 'only one owner shard may be in flight');
  }
  for (const key of [
    'requireReplicaCaughtUp',
    'requireCapacityReport',
    'requireHealthGate',
    'autoRollback'
  ]) {
    if (policy[key] !== true) fail('policy-' + key, key + ' must be true');
  }
  if (cells.length < 1) fail('cells', 'at least one cell is required');

  const hostIds = new Map();
  const cellIds = new Set();
  const ownersByShard = new Map();

  cells.forEach((raw, index) => {
    const cell = raw && typeof raw === 'object' ? raw : {};
    const label = 'cell[' + index + ']';
    const id = String(cell.id || '');
    const host = String(cell.host || '');
    const failureDomain = String(cell.failureDomain || '');
    const servicePrefix = String(cell.servicePrefix || '');
    const dataRoot = String(cell.dataRoot || '');
    const replicas = normalizeInts(cell.replicaShards);
    const owners = normalizeInts(cell.ownerShards);
    const ports = normalizePorts(cell.ports, shardCount);

    if (!id) fail(label + '-id', 'cell id is required');
    if (cellIds.has(id)) fail(label + '-id-duplicate', 'duplicate cell id: ' + id);
    cellIds.add(id);
    if (!host) fail(label + '-host', 'cell host is required');
    if (host && hostIds.has(host)) {
      fail(label + '-host-duplicate',
        'host ' + host + ' is already used by cell ' + hostIds.get(host));
    }
    if (host) hostIds.set(host, id);
    if (!failureDomain) {
      fail(label + '-failure-domain', 'failureDomain is required');
    } else if (/unverified/i.test(failureDomain)) {
      warn(label + '-failure-domain-unverified',
        'failureDomain must be verified before production deployment');
    }
    if (!servicePrefix) fail(label + '-service-prefix', 'servicePrefix is required');
    if (!dataRoot.startsWith('/')) fail(label + '-data-root', 'dataRoot must be absolute');
    if (replicas.length !== shardCount) {
      fail(label + '-replicas', 'cell must retain every logical shard as a replica');
    }
    if (owners.some((shard) => !replicas.includes(shard))) {
      fail(label + '-owner-not-replica', 'owner shard must also exist as a local replica');
    }
    if (ports.length !== shardCount || ports.some((port) => !Number.isInteger(port) || port <= 0)) {
      fail(label + '-ports', 'ports must contain one valid port per shard');
    }
    const uniquePorts = new Set(ports.filter((port) => port > 0));
    if (uniquePorts.size !== ports.filter((port) => port > 0).length) {
      fail(label + '-ports-duplicate', 'ports must be unique inside a cell');
    }
    owners.forEach((shard) => {
      if (!ownersByShard.has(shard)) ownersByShard.set(shard, []);
      ownersByShard.get(shard).push(id);
    });
  });

  for (let shard = 0; shard < shardCount; shard += 1) {
    const owners = ownersByShard.get(shard) || [];
    if (owners.length !== 1) {
      fail('owner-coverage-' + shard,
        'shard ' + shard + ' must have exactly one owner; found ' + owners.join(','));
    }
  }

  const deploymentEligible = failures.length === 0
    && !(policy.requireVerifiedFailureDomains === true && warnings.length > 0);
  return {
    ok: failures.length === 0,
    failures,
    warnings,
    deploymentEligible,
    normalized: {
      version,
      topologyId,
      shardCount,
      routePlanHash,
      routePlanFileSha256,
      releaseId: String(release.id || ''),
      codeSha256: String(release.codeSha256 || '').toLowerCase(),
      policy,
      cells: cells.map((cell) => ({
        id: String(cell.id || ''),
        host: String(cell.host || ''),
        failureDomain: String(cell.failureDomain || ''),
        servicePrefix: String(cell.servicePrefix || ''),
        dataRoot: String(cell.dataRoot || ''),
        replicaShards: normalizeInts(cell.replicaShards),
        ownerShards: normalizeInts(cell.ownerShards),
        ports: normalizePorts(cell.ports, shardCount)
      }))
    }
  };
}

function buildFleetReleasePlan(input, options) {
  const validation = validateFleetPlan(input);
  if (!validation.ok) {
    const error = new Error('fleet plan validation failed');
    error.failures = validation.failures;
    throw error;
  }
  const opts = options || {};
  const plan = validation.normalized;
  const ownerByShard = new Map();
  plan.cells.forEach((cell) => {
    cell.ownerShards.forEach((shard) => ownerByShard.set(shard, cell));
  });
  const canaryShard = Number.isInteger(Number(opts.canaryShard))
    ? Number(opts.canaryShard)
    : 0;
  if (canaryShard < 0 || canaryShard >= plan.shardCount) {
    throw new Error('canaryShard is outside the fleet topology');
  }

  const steps = [];
  let wave = 0;
  const push = (cell, shard, role) => {
    wave += 1;
    steps.push({
      wave,
      releaseId: plan.releaseId,
      topologyId: plan.topologyId,
      host: cell.host,
      cellId: cell.id,
      shardId: shard,
      role,
      service: cell.servicePrefix + '@' + shard + '.service',
      port: cell.ports[shard],
      dataRoot: cell.dataRoot,
      preconditions: role === 'replica'
        ? ['replica-caught-up', 'capacity-fresh', 'health-pass']
        : ['replica-caught-up', 'capacity-fresh', 'health-pass', 'single-owner-in-flight'],
      rollback: 'restore-previous-release-and-health-check'
    });
  };

  for (let shard = 0; shard < plan.shardCount; shard += 1) {
    const owner = ownerByShard.get(shard);
    plan.cells
      .filter((cell) => cell.id !== owner.id && cell.replicaShards.includes(shard))
      .forEach((cell) => push(cell, shard, 'replica'));
  }

  push(ownerByShard.get(canaryShard), canaryShard, 'owner-canary');
  for (let shard = 0; shard < plan.shardCount; shard += 1) {
    if (shard === canaryShard) continue;
    push(ownerByShard.get(shard), shard, 'owner');
  }

  const ownerSteps = steps.filter((step) => step.role !== 'replica');
  if (ownerSteps.length !== plan.shardCount) {
    throw new Error('owner release coverage mismatch');
  }
  const result = {
    version: 1,
    topologyId: plan.topologyId,
    routePlanHash: plan.routePlanHash,
    routePlanFileSha256: plan.routePlanFileSha256,
    releaseId: plan.releaseId,
    codeSha256: plan.codeSha256,
    canaryShard,
    policy: plan.policy,
    warnings: validation.warnings,
    deploymentEligible: validation.deploymentEligible,
    cellCount: plan.cells.length,
    shardCount: plan.shardCount,
    stepCount: steps.length,
    steps
  };
  result.planHash = fleetDigest(result);
  return result;
}

module.exports = {
  validateFleetPlan,
  buildFleetReleasePlan,
  fleetDigest
};
