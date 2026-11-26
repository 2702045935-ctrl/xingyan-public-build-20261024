'use strict';

const crypto = require('crypto');

function stable(value) {
  if (value === null || typeof value !== 'object') {
    return JSON.stringify(value === undefined ? null : value);
  }
  if (Array.isArray(value)) return '[' + value.map(stable).join(',') + ']';
  return '{' + Object.keys(value).sort().map((key) =>
    JSON.stringify(key) + ':' + stable(value[key])
  ).join(',') + '}';
}

function digest(value) {
  return crypto.createHash('sha256').update(stable(value)).digest('hex');
}

function score(text) {
  return crypto.createHash('sha256').update(String(text)).digest()
    .readUIntBE(0, 6);
}

function normalizeCells(cells) {
  return (Array.isArray(cells) ? cells : []).map((cell, index) => ({
    id: String(cell && cell.id || 'cell-' + index),
    host: String(cell && cell.host || ''),
    weight: Math.max(0.1, Number(cell && cell.weight) || 1),
    replicaCount: Math.max(1, Number(cell && cell.replicaCount) || 1)
  })).sort((left, right) => left.id.localeCompare(right.id));
}

function buildLogicalShardDirectory(options) {
  const opts = options || {};
  const logicalShardCount = Math.floor(Number(opts.logicalShardCount));
  const topologyId = String(opts.topologyId || '').trim();
  const routingNamespace = String(opts.routingNamespace || topologyId).trim();
  const cells = normalizeCells(opts.cells);
  const failures = [];
  if (!topologyId) failures.push({ code: 'topology-id' });
  if (!routingNamespace) failures.push({ code: 'routing-namespace' });
  if (!Number.isInteger(logicalShardCount)
      || logicalShardCount < 1
      || logicalShardCount > 16384) {
    failures.push({ code: 'logical-shard-count' });
  }
  if (!cells.length) failures.push({ code: 'cells' });
  if (new Set(cells.map((cell) => cell.id)).size !== cells.length) {
    failures.push({ code: 'duplicate-cell-id' });
  }
  if (new Set(cells.map((cell) => cell.host).filter(Boolean)).size
      !== cells.filter((cell) => cell.host).length) {
    failures.push({ code: 'duplicate-host' });
  }
  if (failures.length) {
    return { version: 1, ok: false, failures };
  }

  const shards = Array.from({ length: logicalShardCount }, (_, id) => {
    const ranked = cells.map((cell) => ({
      id: cell.id,
      score: score(topologyId + '|' + id + '|' + cell.id) * cell.weight
    })).sort((left, right) =>
      right.score - left.score || left.id.localeCompare(right.id)
    );
    const primary = ranked[0].id;
    const replicas = ranked.slice(1)
      .slice(0, Math.max(1, Math.min(cells.length - 1,
        Math.max(...cells.map((cell) => cell.replicaCount)))))
      .map((row) => row.id);
    return { id, primary, replicas };
  });
  const coverage = {};
  for (const cell of cells) coverage[cell.id] = 0;
  for (const shard of shards) coverage[shard.primary] += 1;
  const ideal = logicalShardCount / cells.length;
  const maxDeviation = Math.max(...Object.values(coverage).map((count) =>
    ideal > 0 ? Math.abs(count - ideal) / ideal : 0
  ));
  const directory = {
    version: 1,
    topologyId,
    routingNamespace,
    logicalShardCount,
    cells,
    shards,
    coverage,
    maxDeviation,
    immutableRouting: true
  };
  return Object.assign({
    ok: true,
    failures: [],
    hash: digest(directory)
  }, directory);
}

function validateDirectoryTransition(previous, next) {
  const failures = [];
  if (!previous || previous.ok !== true || !next || next.ok !== true) {
    failures.push({ code: 'invalid-directory' });
  }
  if (previous && next
      && Number(previous.logicalShardCount) !== Number(next.logicalShardCount)) {
    failures.push({
      code: 'logical-shard-count-changed',
      previous: previous.logicalShardCount,
      next: next.logicalShardCount
    });
  }
  if (previous && next
      && String(previous.topologyId) === String(next.topologyId)
      && String(previous.hash) !== String(next.hash)) {
    failures.push({ code: 'same-topology-different-directory' });
  }
  return { ok: failures.length === 0, failures };
}

function logicalShardForKey(directory, key) {
  if (!directory || directory.ok !== true || !directory.logicalShardCount) {
    throw new Error('valid logical shard directory is required');
  }
  return score(String(directory.routingNamespace) + '|route|' + String(key))
    % directory.logicalShardCount;
}

function lookup(directory, key) {
  const logicalShard = logicalShardForKey(directory, key);
  return Object.assign({ key: String(key), logicalShard },
    directory.shards[logicalShard]);
}

module.exports = {
  buildLogicalShardDirectory,
  validateDirectoryTransition,
  logicalShardForKey,
  lookup
};
