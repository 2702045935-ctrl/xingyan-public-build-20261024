'use strict';

const crypto = require('crypto');
const { validateFleetPlan } = require('./fleet-release-plan');

function score(value) {
  return crypto.createHash('sha256').update(String(value)).digest()
    .readUIntBE(0, 6);
}

function normalizeAdded(cell, index, source) {
  const id = String(cell && cell.id || '');
  const host = String(cell && cell.host || '');
  const failureDomain = String(cell && cell.failureDomain || '');
  const servicePrefix = String(cell && cell.servicePrefix || '');
  const dataRoot = String(cell && cell.dataRoot || '');
  const ports = Array.isArray(cell && cell.ports) ? cell.ports.map(Number) : [];
  if (!id || !host || !failureDomain || !servicePrefix || !dataRoot) {
    throw new Error('expansion cell ' + index + ' is incomplete');
  }
  if (/unverified/i.test(failureDomain)) {
    throw new Error('expansion cell failure domain is unverified');
  }
  if (ports.length !== source.shardCount
      || ports.some((port) => !Number.isInteger(port) || port <= 0)) {
    throw new Error('expansion cell ports are invalid');
  }
  return {
    id,
    host,
    failureDomain,
    servicePrefix,
    dataRoot,
    replicaShards: Array.from({ length: source.shardCount }, (_, shard) => shard),
    ownerShards: [],
    ports
  };
}

function buildExpandedFleetPlan(sourceInput, additions, options) {
  const opts = options || {};
  const sourceValidation = validateFleetPlan(sourceInput);
  if (!sourceValidation.ok) throw new Error('source fleet plan is invalid');
  const source = sourceValidation.normalized;
  const verifiedDomains = opts.verifiedDomains || {};
  const cells = source.cells.map((cell) => {
    const domain = String(verifiedDomains[cell.id] || '');
    return Object.assign({}, cell, {
      failureDomain: domain || cell.failureDomain,
      ownerShards: [],
      replicaShards: Array.from({ length: source.shardCount }, (_, shard) => shard)
    });
  });
  const extra = (Array.isArray(additions) ? additions : []).map(
    (cell, index) => normalizeAdded(cell, index, source)
  );
  cells.push(...extra);
  if (cells.length <= source.cells.length) {
    throw new Error('expansion must add at least one cell');
  }
  if (new Set(cells.map((cell) => cell.id)).size !== cells.length
      || new Set(cells.map((cell) => cell.host)).size !== cells.length) {
    throw new Error('expansion contains duplicate cell id or host');
  }
  const topologyId = String(opts.topologyId
    || source.topologyId.replace(/-expanded-\d+$/, '')
      + '-expanded-' + cells.length);
  for (let shard = 0; shard < source.shardCount; shard += 1) {
    const owner = cells.map((cell) => ({
      id: cell.id,
      score: score(topologyId + '|' + shard + '|' + cell.id)
    })).sort((left, right) =>
      right.score - left.score || left.id.localeCompare(right.id)
    )[0];
    cells.find((cell) => cell.id === owner.id).ownerShards.push(shard);
  }
  const target = {
    version: 1,
    topologyId,
    routePlanHash: source.routePlanHash,
    routePlanFileSha256: source.routePlanFileSha256,
    shardCount: source.shardCount,
    release: Object.assign({}, sourceInput.release || {}),
    policy: Object.assign({}, source.policy, {
      maxOwnerShardsInFlight: 1,
      requireReplicaCaughtUp: true,
      requireCapacityReport: true,
      requireHealthGate: true,
      autoRollback: true,
      requireVerifiedFailureDomains: true
    }),
    cells
  };
  const validation = validateFleetPlan(target);
  if (!validation.ok || !validation.deploymentEligible) {
    const error = new Error('expanded fleet plan is not deployment eligible');
    error.failures = validation.failures;
    error.warnings = validation.warnings;
    throw error;
  }
  return Object.assign({}, target, {
    deploymentEligible: validation.deploymentEligible,
    warnings: validation.warnings
  });
}

module.exports = { buildExpandedFleetPlan };
