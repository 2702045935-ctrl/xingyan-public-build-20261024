'use strict';

const crypto = require('crypto');

const DEFAULT_POLICY = Object.freeze({
  expectedShards: 7,
  maxMemoryUsedRatio: 0.75,
  minFreeMemoryBytes: 512 * 1024 * 1024,
  maxLoadPerCore: 0.8,
  maxDiskUsedRatio: 0.8,
  maxInodeUsedRatio: 0.8,
  maxFdsPerProcess: 50000
});

function stable(value) {
  if (value === null || typeof value !== 'object') {
    return JSON.stringify(value === undefined ? null : value);
  }
  if (Array.isArray(value)) return '[' + value.map(stable).join(',') + ']';
  return '{' + Object.keys(value).sort().map((key) =>
    JSON.stringify(key) + ':' + stable(value[key])
  ).join(',') + '}';
}

function hash(value) {
  return crypto.createHash('sha256').update(stable(value)).digest('hex');
}

function number(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function evaluateSingleCellCapacity(input, policyInput) {
  const data = input || {};
  const policy = Object.assign({}, DEFAULT_POLICY, policyInput || {});
  const host = data.host || {};
  const disk = host.disk || {};
  const shards = Array.isArray(data.shards) ? data.shards : [];
  const failures = [];
  const fail = (code, details) => failures.push(Object.assign({ code }, details || {}));

  const cpuCount = Math.floor(number(host.cpuCount));
  const totalMemoryBytes = number(host.totalMemoryBytes);
  const freeMemoryBytes = number(host.freeMemoryBytes);
  const load1 = number(host.load1);
  const diskTotalBytes = number(disk.totalBytes);
  const diskFreeBytes = number(disk.freeBytes);
  const inodesTotal = number(disk.inodesTotal);
  const inodesFree = number(disk.inodesFree);

  if (cpuCount < 1) fail('cpu-count');
  if (totalMemoryBytes < 1) fail('total-memory');
  if (freeMemoryBytes < 0 || freeMemoryBytes > totalMemoryBytes) fail('free-memory');
  if (load1 < 0) fail('load1');
  if (diskTotalBytes < 1) fail('disk-total');
  if (diskFreeBytes < 0 || diskFreeBytes > diskTotalBytes) fail('disk-free');
  if (inodesTotal < 1) fail('inodes-total');
  if (inodesFree < 0 || inodesFree > inodesTotal) fail('inodes-free');
  if (shards.length !== policy.expectedShards) {
    fail('shard-count', { expected: policy.expectedShards, actual: shards.length });
  }

  const ids = new Set();
  const pids = new Set();
  let shardRssBytes = 0;
  for (const shard of shards) {
    const id = Number(shard && shard.id);
    const pid = Number(shard && shard.pid);
    const rssBytes = number(shard && shard.rssBytes);
    const fdCount = number(shard && shard.fdCount);
    if (!Number.isInteger(id) || id < 0) fail('shard-id', { value: shard && shard.id });
    if (ids.has(id)) fail('shard-id-duplicate', { id });
    ids.add(id);
    if (!Number.isInteger(pid) || pid <= 0) fail('shard-pid', { id, pid });
    if (pids.has(pid)) fail('process-pid-duplicate', { pid });
    pids.add(pid);
    if (rssBytes <= 0) fail('shard-rss', { id, rssBytes });
    if (fdCount < 0) fail('shard-fds', { id, fdCount });
    if (fdCount > policy.maxFdsPerProcess) {
      fail('shard-fds-high', { id, fdCount, max: policy.maxFdsPerProcess });
    }
    shardRssBytes += Math.max(0, rssBytes);
  }
  for (let id = 0; id < policy.expectedShards; id += 1) {
    if (!ids.has(id)) fail('shard-missing', { id });
  }

  const usedMemoryBytes = totalMemoryBytes - freeMemoryBytes;
  const memoryUsedRatio = totalMemoryBytes > 0 ? usedMemoryBytes / totalMemoryBytes : 1;
  const shardRssRatio = totalMemoryBytes > 0 ? shardRssBytes / totalMemoryBytes : 1;
  const loadPerCore = cpuCount > 0 ? load1 / cpuCount : Infinity;
  const diskUsedRatio = diskTotalBytes > 0
    ? (diskTotalBytes - diskFreeBytes) / diskTotalBytes
    : 1;
  const inodeUsedRatio = inodesTotal > 0
    ? (inodesTotal - inodesFree) / inodesTotal
    : 1;
  if (freeMemoryBytes < policy.minFreeMemoryBytes) {
    fail('free-memory-low', {
      freeMemoryBytes,
      minimum: policy.minFreeMemoryBytes
    });
  }
  if (memoryUsedRatio > policy.maxMemoryUsedRatio) {
    fail('memory-used-high', {
      ratio: memoryUsedRatio,
      maximum: policy.maxMemoryUsedRatio
    });
  }
  if (loadPerCore > policy.maxLoadPerCore) {
    fail('load-per-core-high', {
      loadPerCore,
      maximum: policy.maxLoadPerCore
    });
  }
  if (diskUsedRatio > policy.maxDiskUsedRatio) {
    fail('disk-used-high', {
      ratio: diskUsedRatio,
      maximum: policy.maxDiskUsedRatio
    });
  }
  if (inodeUsedRatio > policy.maxInodeUsedRatio) {
    fail('inode-used-high', {
      ratio: inodeUsedRatio,
      maximum: policy.maxInodeUsedRatio
    });
  }

  const result = {
    version: 1,
    ok: failures.length === 0,
    host: {
      cpuCount,
      totalMemoryBytes,
      freeMemoryBytes,
      load1,
      memoryUsedRatio,
      shardRssBytes,
      shardRssRatio,
      loadPerCore,
      diskUsedRatio,
      inodeUsedRatio
    },
    shards: shards.map((shard) => ({
      id: Number(shard.id),
      pid: Number(shard.pid),
      rssBytes: number(shard.rssBytes),
      fdCount: number(shard.fdCount)
    })),
    policy,
    failures
  };
  result.fingerprint = hash({
    host: result.host,
    shards: result.shards,
    policy,
    failures
  });
  return result;
}

module.exports = {
  DEFAULT_POLICY,
  evaluateSingleCellCapacity
};
