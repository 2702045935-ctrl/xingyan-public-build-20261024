'use strict';

const assert = require('assert');
const {
  expandManifestShards,
  parseMeminfo,
  parseProcStatus
} = require('../lib/single-cell-capacity-collector');

const shards = expandManifestShards({
  serviceTemplate: 'xingyan-mainline-shard@{id}.service',
  shardCount: 7,
  backendBasePort: 7080,
  portStep: 100
});
assert.strictEqual(shards.length, 7);
assert.deepStrictEqual(shards.map((row) => row.backendPort),
  [7080, 7180, 7280, 7380, 7480, 7580, 7680]);
assert.strictEqual(shards[3].service, 'xingyan-mainline-shard@3.service');

const memory = parseMeminfo([
  'MemTotal:       8388608 kB',
  'MemFree:         1048576 kB',
  'MemAvailable:    3145728 kB'
].join('\n'));
assert.strictEqual(memory.totalMemoryBytes, 8 * 1024 * 1024 * 1024);
assert.strictEqual(memory.freeMemoryBytes, 3 * 1024 * 1024 * 1024);

const proc = parseProcStatus([
  'Name:\tnode',
  'VmRSS:\t  358400 kB',
  'Threads:\t24'
].join('\n'));
assert.strictEqual(proc.rssBytes, 358400 * 1024);

console.log('single-cell-capacity-collector: passed');
