'use strict';

const path = require('path');
const { loadManifest } = require('../lib/shard-runtime-manifest');

const root = path.resolve(__dirname, '..');
const manifestFile = process.argv[2]
  ? path.resolve(process.argv[2])
  : path.join(root, 'shard-runtime-production.json');
const topologyFile = path.join(root, 'shard-topologies.json');
const result = loadManifest(manifestFile, { topologyFile });

console.log(JSON.stringify({
  ok: result.ok,
  file: result.file,
  hash: result.hash,
  environment: result.manifest.environment,
  topologyId: result.manifest.topologyId,
  shardCount: result.manifest.shardCount,
  frozenDate: result.manifest.frozenDate,
  frozenCodeHash: result.manifest.frozenCodeHash,
  shards: result.manifest.shards,
  failures: result.failures
}, null, 2));

if (!result.ok) process.exitCode = 1;
