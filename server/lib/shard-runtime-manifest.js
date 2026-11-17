'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { resolveTopology } = require('./shard-topology');

function canonical(value) {
  if (value === null || typeof value !== 'object') {
    return JSON.stringify(value === undefined ? null : value);
  }
  if (Array.isArray(value)) {
    return '[' + value.map(canonical).join(',') + ']';
  }
  return '{' + Object.keys(value).sort().map((key) =>
    JSON.stringify(key) + ':' + canonical(value[key])
  ).join(',') + '}';
}

function manifestHash(value) {
  return crypto.createHash('sha256').update(canonical(value)).digest('hex');
}

function absolutePath(value, name, failures) {
  const text = String(value || '');
  if (!text.startsWith('/')) {
    failures.push({ name, message: 'must be an absolute path', value: text });
  }
  return path.posix.normalize(text);
}

function integer(value, name, min, failures) {
  const number = Number(value);
  if (!Number.isInteger(number) || number < min) {
    failures.push({ name, message: 'must be an integer >= ' + min, value });
  }
  return number;
}

function normalizeManifest(manifest, options) {
  const opts = options || {};
  const failures = [];
  const source = manifest && typeof manifest === 'object' ? manifest : {};
  if (Number(source.version) !== 1) {
    failures.push({ name: 'version', message: 'unsupported manifest version', value: source.version });
  }
  const environment = String(source.environment || '').trim();
  if (!environment) failures.push({ name: 'environment', message: 'required' });
  const topologyId = String(source.topologyId || '').trim();
  if (!topologyId) failures.push({ name: 'topologyId', message: 'required' });
  const host = String(source.host || '').trim();
  if (!host) failures.push({ name: 'host', message: 'required' });
  const entryHost = String(source.entryHost || '').trim();
  if (!entryHost) failures.push({ name: 'entryHost', message: 'required' });
  const serviceTemplate = String(source.serviceTemplate || '').trim();
  if (!serviceTemplate.includes('{id}')) {
    failures.push({ name: 'serviceTemplate', message: 'must contain {id}' });
  }
  const shardCount = integer(source.shardCount, 'shardCount', 2, failures);
  const backendBasePort = integer(source.backendBasePort, 'backendBasePort', 1, failures);
  const entryBasePort = integer(source.entryBasePort, 'entryBasePort', 1, failures);
  const portStep = integer(source.portStep, 'portStep', 1, failures);
  const programDir = absolutePath(source.programDir, 'programDir', failures);
  const dataDir = absolutePath(source.dataDir, 'dataDir', failures);
  const frozenDate = String(source.frozenDate || '').trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(frozenDate)) {
    failures.push({ name: 'frozenDate', message: 'must be YYYY-MM-DD', value: frozenDate });
  }
  const frozenCodeHash = String(source.frozenCodeHash || '').trim().toLowerCase();
  if (!/^[a-f0-9]{64}$/.test(frozenCodeHash)) {
    failures.push({ name: 'frozenCodeHash', message: 'must be a SHA256 hex digest', value: frozenCodeHash });
  }
  const rows = [];
  if (Number.isInteger(shardCount) && shardCount > 0) {
    for (let id = 0; id < shardCount; id += 1) {
      rows.push({
        id,
        service: serviceTemplate.replace(/\{id\}/g, String(id)),
        backendPort: backendBasePort + id * portStep,
        entryPort: entryBasePort + id * portStep
      });
    }
  }
  const serviceNames = new Set();
  const backendPorts = new Set();
  const entryPorts = new Set();
  for (const row of rows) {
    if (serviceNames.has(row.service)) {
      failures.push({ name: 'service', message: 'duplicate service', value: row.service });
    }
    if (backendPorts.has(row.backendPort)) {
      failures.push({ name: 'backendPort', message: 'duplicate port', value: row.backendPort });
    }
    if (entryPorts.has(row.entryPort)) {
      failures.push({ name: 'entryPort', message: 'duplicate port', value: row.entryPort });
    }
    serviceNames.add(row.service);
    backendPorts.add(row.backendPort);
    entryPorts.add(row.entryPort);
  }
  let topology = null;
  if (topologyId && opts.topologyFile) {
    try {
      topology = resolveTopology(opts.topologyFile, topologyId);
    } catch (error) {
      failures.push({ name: 'topologyId', message: error.message, value: topologyId });
    }
  }
  if (topology) {
    if (topology.shardCount !== shardCount) {
      failures.push({
        name: 'topologyShardCount',
        message: 'manifest and topology differ',
        expected: shardCount,
        actual: topology.shardCount
      });
    }
    const expected = rows.map((row) => row.backendPort);
    if (canonical(expected) !== canonical(topology.ports)) {
      failures.push({
        name: 'topologyPorts',
        message: 'manifest backend ports do not match topology',
        expected,
        actual: topology.ports
      });
    }
  }
  const normalized = {
    version: 1,
    environment,
    topologyId,
    host,
    entryHost,
    programDir,
    dataDir,
    serviceTemplate,
    shardCount,
    backendBasePort,
    entryBasePort,
    portStep,
    frozenDate,
    frozenCodeHash,
    shards: rows,
    topology
  };
  return {
    ok: failures.length === 0,
    failures,
    manifest: normalized,
    hash: manifestHash(normalized)
  };
}

function loadManifest(file, options) {
  const manifestFile = path.resolve(String(file || ''));
  const raw = JSON.parse(fs.readFileSync(manifestFile, 'utf8'));
  return Object.assign({
    file: manifestFile
  }, normalizeManifest(raw, options));
}

function assertRunningShard(manifestResult, options) {
  if (!manifestResult || manifestResult.ok !== true || !manifestResult.manifest) {
    throw new Error('shard runtime manifest is invalid');
  }
  const shardId = Number(options && options.shardId);
  const port = Number(options && options.port);
  const runtimeBasePort = Number(options && options.runtimeBasePort);
  if (!Number.isInteger(shardId)) throw new Error('SHARD_ID must be an integer');
  if (!Number.isInteger(port) || port <= 0) throw new Error('PORT must be a positive integer');
  const shard = manifestResult.manifest.shards.find((row) => row.id === shardId);
  if (!shard) throw new Error('SHARD_ID ' + shardId + ' is not in the runtime manifest');
  const expectedRuntimePort = Number.isInteger(runtimeBasePort) && runtimeBasePort > 0
    ? runtimeBasePort + shardId * 100
    : shard.backendPort;
  if (expectedRuntimePort !== port) {
    throw new Error('runtime port mismatch: shard=' + shardId
      + ' expected=' + expectedRuntimePort + ' actual=' + port);
  }
  return {
    manifestHash: manifestResult.hash,
    environment: manifestResult.manifest.environment,
    topologyId: manifestResult.manifest.topologyId,
    shardId,
    service: shard.service,
    backendPort: shard.backendPort,
    runtimeBasePort: Number.isInteger(runtimeBasePort) && runtimeBasePort > 0
      ? runtimeBasePort
      : null,
    runtimePort: port,
    entryPort: shard.entryPort,
    frozenCodeHash: manifestResult.manifest.frozenCodeHash
  };
}

module.exports = {
  canonical,
  manifestHash,
  normalizeManifest,
  loadManifest,
  assertRunningShard
};
