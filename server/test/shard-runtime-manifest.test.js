'use strict';

const assert = require('assert');
const path = require('path');
const { normalizeManifest, loadManifest, manifestHash } = require('../lib/shard-runtime-manifest');

const root = path.resolve(__dirname, '..');
const topologyFile = path.join(root, 'shard-topologies.json');
const manifestFile = path.join(root, 'shard-runtime-production.json');
const loaded = loadManifest(manifestFile, { topologyFile });

assert.strictEqual(loaded.ok, true, JSON.stringify(loaded.failures));
assert.strictEqual(loaded.manifest.shardCount, 7);
assert.strictEqual(loaded.manifest.topologyId, 'server-b-mainline-shards-7');
assert.strictEqual(loaded.manifest.frozenDate, '2026-11-16');
assert.match(loaded.manifest.frozenCodeHash, /^[a-f0-9]{64}$/);
assert.deepStrictEqual(
  loaded.manifest.shards.map((row) => row.backendPort),
  [7080, 7180, 7280, 7380, 7480, 7580, 7680]
);
assert.deepStrictEqual(
  loaded.manifest.shards.map((row) => row.entryPort),
  [15299, 15399, 15499, 15599, 15699, 15799, 15899]
);
assert.strictEqual(loaded.hash, manifestHash(loaded.manifest));

const wrongPort = normalizeManifest({
  version: 1,
  environment: 'test',
  topologyId: 'server-b-mainline-shards-7',
  host: '127.0.0.1',
  entryHost: '127.0.0.1',
  programDir: '/srv/app',
  dataDir: '/srv/data',
  serviceTemplate: 'shard@{id}.service',
  shardCount: 7,
  backendBasePort: 7081,
  entryBasePort: 15299,
  portStep: 100,
  frozenDate: '2026-11-16',
  frozenCodeHash: 'a'.repeat(64)
}, { topologyFile });
assert.strictEqual(wrongPort.ok, false);
assert.ok(wrongPort.failures.some((row) => row.name === 'topologyPorts'));

const relativePath = normalizeManifest({
  version: 1,
  environment: 'test',
  topologyId: 'server-b-mainline-shards-7',
  host: '127.0.0.1',
  entryHost: '127.0.0.1',
  programDir: 'srv/app',
  dataDir: '/srv/data',
  serviceTemplate: 'shard@{id}.service',
  shardCount: 7,
  backendBasePort: 7080,
  entryBasePort: 15299,
  portStep: 100,
  frozenDate: '2026-11-16',
  frozenCodeHash: 'a'.repeat(64)
}, { topologyFile });
assert.strictEqual(relativePath.ok, false);
assert.ok(relativePath.failures.some((row) => row.name === 'programDir'));

console.log('shard-runtime-manifest: passed');
