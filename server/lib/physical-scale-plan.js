'use strict';

const crypto = require('crypto');
const { validateFleetPlan } = require('./fleet-release-plan');

function digest(value) {
  return crypto.createHash('sha256')
    .update(JSON.stringify(value))
    .digest('hex');
}

function ownerMap(plan) {
  const out = new Map();
  for (const cell of plan.cells) {
    for (const shard of cell.ownerShards) out.set(shard, cell);
  }
  return out;
}

function buildPhysicalScalePlan(sourceInput, targetInput, options) {
  const opts = options || {};
  const sourceValidation = validateFleetPlan(sourceInput);
  const targetValidation = validateFleetPlan(targetInput);
  if (!sourceValidation.ok || !targetValidation.ok) {
    return {
      version: 1,
      ok: false,
      failures: sourceValidation.failures.concat(targetValidation.failures)
    };
  }
  const source = sourceValidation.normalized;
  const target = targetValidation.normalized;
  const failures = [];
  const sourceCells = new Map(source.cells.map((cell) => [cell.id, cell]));
  const targetCells = new Map(target.cells.map((cell) => [cell.id, cell]));
  const addedCells = target.cells.filter((cell) => !sourceCells.has(cell.id));
  const removedCells = source.cells.filter((cell) => !targetCells.has(cell.id));
  if (target.cells.length <= source.cells.length) {
    failures.push({ code: 'no-physical-expansion' });
  }
  if (!addedCells.length) failures.push({ code: 'no-new-cells' });
  if (removedCells.length) failures.push({ code: 'source-cell-removed' });
  if (source.shardCount !== target.shardCount) {
    failures.push({ code: 'logical-shard-count-changed' });
  }
  if (!targetValidation.deploymentEligible) {
    failures.push({ code: 'target-not-production-eligible' });
  }

  const sourceOwners = ownerMap(source);
  const targetOwners = ownerMap(target);
  const moves = [];
  for (let shard = 0; shard < source.shardCount; shard += 1) {
    const from = sourceOwners.get(shard);
    const to = targetOwners.get(shard);
    if (!from || !to) {
      failures.push({ code: 'owner-missing', shard });
      continue;
    }
    if (from.id === to.id) continue;
    if (!to.replicaShards.includes(shard)) {
      failures.push({ code: 'target-owner-not-replica', shard, cellId: to.id });
      continue;
    }
    moves.push({
      shard,
      fromCellId: from.id,
      fromHost: from.host,
      toCellId: to.id,
      toHost: to.host,
      service: to.servicePrefix + '@' + shard + '.service',
      port: to.ports[shard],
      dataRoot: to.dataRoot
    });
  }
  const maxMoves = Math.max(
    1, Math.min(target.shardCount, Number(opts.maxShardMoves) || target.shardCount)
  );
  if (moves.length > maxMoves) failures.push({ code: 'too-many-shard-moves' });
  if (failures.length) {
    return {
      version: 1,
      ok: false,
      failures: failures.slice(0, 500),
      sourceCellCount: source.cells.length,
      targetCellCount: target.cells.length,
      moves
    };
  }

  const stages = [];
  const add = (stage, rows) => {
    for (const row of rows) stages.push(Object.assign({ stage }, row));
  };
  add('prepare-node', addedCells.map((cell) => ({
    cellId: cell.id,
    host: cell.host,
    servicePrefix: cell.servicePrefix,
    dataRoot: cell.dataRoot,
    gates: ['host-registered', 'unique-failure-domain', 'disk-inodes-pass', 'code-hash-pass']
  })));
  add('seed-replica', moves.map((move) => ({
    shard: move.shard,
    cellId: move.toCellId,
    host: move.toHost,
    gate: 'replica-seeded'
  })));
  add('catch-up', moves.map((move) => ({
    shard: move.shard,
    fromCellId: move.fromCellId,
    toCellId: move.toCellId,
    gate: 'replica-lag-zero'
  })));
  add('shadow-read', moves.map((move) => ({
    shard: move.shard,
    gate: 'shadow-read-zero-diff'
  })));
  for (const move of moves) {
    add('cutover', [{
      shard: move.shard,
      fromCellId: move.fromCellId,
      toCellId: move.toCellId,
      steps: [
        'freeze-old-owner-writes',
        'verify-replica-lag-zero',
        'acquire-target-lease',
        'switch-chat-owner-routes',
        'switch-gateway-mapping',
        'unfreeze-target-owner',
        'verify-single-owner',
        'verify-message-continuity',
        'switch-replication-topology'
      ],
      rollback: [
        'freeze-target-owner-writes',
        'restore-gateway-mapping',
        'restore-chat-owner-routes',
        'release-target-lease',
        'unfreeze-old-owner',
        'restore-replication-topology',
        'verify-old-owner-health'
      ]
    }]);
  }
  add('soak', [{
    durationMinutes: Math.max(1, Number(opts.soakMinutes) || 30),
    gates: ['no-loss', 'no-duplicate', 'no-order-violation', 'p99-pass', 'memory-pass']
  }]);

  const receipt = {
    version: 1,
    sourceTopologyId: source.topologyId,
    targetTopologyId: target.topologyId,
    sourceCellCount: source.cells.length,
    targetCellCount: target.cells.length,
    addedCellCount: addedCells.length,
    shardCount: source.shardCount,
    moveCount: moves.length,
    moves,
    stages
  };
  return Object.assign({
    ok: true,
    failures: [],
    productionEligible: targetValidation.deploymentEligible,
    fingerprint: digest(receipt)
  }, receipt);
}

module.exports = {
  buildPhysicalScalePlan
};
