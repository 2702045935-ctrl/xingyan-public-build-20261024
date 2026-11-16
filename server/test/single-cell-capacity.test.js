'use strict';

const assert = require('assert');
const { evaluateSingleCellCapacity } = require('../lib/single-cell-capacity');

const GiB = 1024 * 1024 * 1024;
const valid = {
  host: {
    cpuCount: 8,
    totalMemoryBytes: 8 * GiB,
    freeMemoryBytes: 3 * GiB,
    load1: 2.4,
    disk: {
      totalBytes: 100 * GiB,
      freeBytes: 40 * GiB,
      inodesTotal: 1000000,
      inodesFree: 600000
    }
  },
  shards: Array.from({ length: 7 }, (_, id) => ({
    id,
    pid: 1000 + id,
    rssBytes: 350 * 1024 * 1024,
    fdCount: 1200
  }))
};

let report = evaluateSingleCellCapacity(valid);
assert.strictEqual(report.ok, true, JSON.stringify(report.failures));
assert.match(report.fingerprint, /^[a-f0-9]{64}$/);
assert.strictEqual(report.shards.length, 7);

const lowMemory = JSON.parse(JSON.stringify(valid));
lowMemory.host.freeMemoryBytes = 300 * 1024 * 1024;
report = evaluateSingleCellCapacity(lowMemory);
assert.ok(report.failures.some((row) => row.code === 'free-memory-low'));

const highLoad = JSON.parse(JSON.stringify(valid));
highLoad.host.load1 = 7;
report = evaluateSingleCellCapacity(highLoad);
assert.ok(report.failures.some((row) => row.code === 'load-per-core-high'));

const highFds = JSON.parse(JSON.stringify(valid));
highFds.shards[3].fdCount = 60000;
report = evaluateSingleCellCapacity(highFds);
assert.ok(report.failures.some((row) => row.code === 'shard-fds-high'));

const duplicatePid = JSON.parse(JSON.stringify(valid));
duplicatePid.shards[6].pid = duplicatePid.shards[5].pid;
report = evaluateSingleCellCapacity(duplicatePid);
assert.ok(report.failures.some((row) => row.code === 'process-pid-duplicate'));

const missingShard = JSON.parse(JSON.stringify(valid));
missingShard.shards.pop();
report = evaluateSingleCellCapacity(missingShard);
assert.ok(report.failures.some((row) => row.code === 'shard-count'));

console.log('single-cell-capacity: passed');
