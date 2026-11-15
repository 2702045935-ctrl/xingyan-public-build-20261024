'use strict';

const crypto = require('crypto');
const { canonical, hash } = require('./shard-snapshot');
const { stableRouteHash } = require('./shard-route-plan');

function textCompare(left, right) {
  const a = String(left == null ? '' : left);
  const b = String(right == null ? '' : right);
  return a < b ? -1 : (a > b ? 1 : 0);
}

function countAssignments(assignments, shardCount) {
  const counts = Array.from({ length: shardCount }, () => 0);
  for (const shard of Object.values(assignments || {})) {
    const index = Number(shard);
    if (Number.isInteger(index) && index >= 0 && index < shardCount) counts[index] += 1;
  }
  return counts;
}

function moveScore(topologyId, key) {
  return stableRouteHash('rebalance-v1|' + topologyId + '|' + key);
}

function buildShardRebalancePlan(options) {
  const opts = options || {};
  const sourceCount = Math.floor(Number(opts.sourceShardCount));
  const targetCount = Math.floor(Number(opts.targetShardCount));
  const topologyId = String(opts.targetTopologyId || '').trim();
  const assignments = opts.assignments && typeof opts.assignments === 'object'
    ? opts.assignments
    : {};
  const failures = [];

  if (!Number.isInteger(sourceCount) || sourceCount < 2) {
    failures.push({ code: 'source-shard-count' });
  }
  if (!Number.isInteger(targetCount) || targetCount <= sourceCount || targetCount > 64) {
    failures.push({ code: 'target-shard-count' });
  }
  if (!topologyId) failures.push({ code: 'target-topology-id' });

  const keys = Object.keys(assignments);
  const bySource = Array.from({ length: Math.max(0, sourceCount) }, () => []);
  for (const key of keys) {
    const shard = Number(assignments[key]);
    if (!Number.isInteger(shard) || shard < 0 || shard >= sourceCount) {
      failures.push({ code: 'invalid-assignment', key, shard });
      continue;
    }
    bySource[shard].push(key);
  }
  if (failures.length) {
    return {
      version: 1,
      ok: false,
      failures: failures.slice(0, 500)
    };
  }

  const added = targetCount - sourceCount;
  const total = keys.length;
  const targetMoves = Math.min(total, Math.round(total * added / targetCount));
  const quotas = bySource.map((rows) => Math.floor(rows.length * added / targetCount));
  let remaining = targetMoves - quotas.reduce((sum, value) => sum + value, 0);
  const remainderOrder = bySource.map((rows, source) => ({
    source,
    remainder: rows.length * added / targetCount - Math.floor(rows.length * added / targetCount)
  })).sort((left, right) =>
    right.remainder - left.remainder || left.source - right.source
  );
  for (let index = 0; remaining > 0; index = (index + 1) % remainderOrder.length) {
    const source = remainderOrder[index].source;
    if (quotas[source] < bySource[source].length) {
      quotas[source] += 1;
      remaining -= 1;
    }
  }
  const selected = [];
  for (let source = 0; source < sourceCount; source += 1) {
    const candidates = bySource[source].slice().sort((left, right) =>
      moveScore(topologyId, left) - moveScore(topologyId, right)
      || textCompare(left, right)
    );
    for (const key of candidates.slice(0, quotas[source])) {
      selected.push({ key, from: source, score: moveScore(topologyId, key) });
    }
  }
  selected.sort((left, right) =>
    left.score - right.score
    || textCompare(left.key, right.key)
  );

  const moves = selected.map((row, index) => ({
    key: row.key,
    from: row.from,
    to: sourceCount + (index % added),
    score: row.score
  }));
  const assignmentsAfter = Object.assign({}, assignments);
  for (const move of moves) assignmentsAfter[move.key] = move.to;
  const before = countAssignments(assignments, sourceCount);
  const after = countAssignments(assignmentsAfter, targetCount);
  const ideal = total / targetCount;
  const deviations = after.map((count) => ideal > 0
    ? Math.abs(count - ideal) / ideal
    : 0
  );
  const maxDeviation = deviations.length ? Math.max(...deviations) : 0;
  const moveDigest = crypto.createHash('sha256').update(canonical(moves.map((move) => ({
    key: move.key,
    from: move.from,
    to: move.to
  })))).digest('hex');
  const deterministic = {
    version: 1,
    sourceShardCount: sourceCount,
    targetShardCount: targetCount,
    targetTopologyId: topologyId,
    total,
    moveCount: moves.length,
    movePct: total > 0 ? moves.length * 100 / total : 0,
    before,
    after,
    idealPerShard: ideal,
    maxDeviation,
    moveDigest,
    assignmentsHash: hash(assignmentsAfter),
    movesPreview: moves.slice(0, 100).map((move) => ({
      key: move.key,
      from: move.from,
      to: move.to
    }))
  };
  return Object.assign({
    ok: true,
    fingerprint: hash(deterministic)
  }, deterministic, {
    assignments: assignmentsAfter,
    moves
  });
}

module.exports = {
  buildShardRebalancePlan
};
