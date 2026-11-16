'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { evaluateSingleCellCapacity } = require('./single-cell-capacity');

function expandManifestShards(manifest) {
  const shardCount = Number(manifest && manifest.shardCount);
  const template = String(manifest && manifest.serviceTemplate || '');
  const backendBasePort = Number(manifest && manifest.backendBasePort);
  const portStep = Number(manifest && manifest.portStep);
  if (!Number.isInteger(shardCount) || shardCount < 1) {
    throw new Error('manifest shardCount is invalid');
  }
  if (!template.includes('{id}')) throw new Error('manifest serviceTemplate is invalid');
  if (!Number.isInteger(backendBasePort) || backendBasePort < 1) {
    throw new Error('manifest backendBasePort is invalid');
  }
  if (!Number.isInteger(portStep) || portStep < 1) {
    throw new Error('manifest portStep is invalid');
  }
  return Array.from({ length: shardCount }, (_, id) => ({
    id,
    service: template.replace(/\{id\}/g, String(id)),
    backendPort: backendBasePort + id * portStep
  }));
}

function parseMeminfo(text) {
  const values = {};
  String(text || '').split('\n').forEach((line) => {
    const match = line.match(/^([^:]+):\s+(\d+)\s+kB$/);
    if (match) values[match[1]] = Number(match[2]) * 1024;
  });
  return {
    totalMemoryBytes: values.MemTotal || 0,
    freeMemoryBytes: values.MemAvailable || values.MemFree || 0
  };
}

function parseProcStatus(text) {
  const match = String(text || '').match(/^VmRSS:\s+(\d+)\s+kB$/m);
  return { rssBytes: match ? Number(match[1]) * 1024 : 0 };
}

function readFile(file, fallback) {
  try { return fs.readFileSync(file, 'utf8'); }
  catch (_) { return fallback || ''; }
}

function collectSingleCellCapacity(options) {
  const opts = options || {};
  const manifestPath = path.resolve(String(opts.manifest || ''));
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const shards = expandManifestShards(manifest);
  const dataDir = path.resolve(String(opts.dataDir || manifest.dataDir || ''));
  const failures = [];
  const rows = shards.map((shard) => {
    const result = spawnSync('systemctl', [
      'show', shard.service, '-p', 'MainPID', '--value'
    ], {
      encoding: 'utf8',
      timeout: 5000,
      windowsHide: true
    });
    const pid = Number(String(result.stdout || '').trim());
    if (result.status !== 0 || !Number.isInteger(pid) || pid <= 0) {
      failures.push({
        code: 'pid-unavailable',
        shardId: shard.id,
        service: shard.service,
        error: String(result.stderr || '').trim()
      });
    }
    const status = pid > 0
      ? parseProcStatus(readFile('/proc/' + pid + '/status'))
      : { rssBytes: 0 };
    let fdCount = 0;
    if (pid > 0) {
      try { fdCount = fs.readdirSync('/proc/' + pid + '/fd').length; }
      catch (_) { failures.push({ code: 'fd-unreadable', shardId: shard.id, pid }); }
    }
    return {
      id: shard.id,
      pid,
      rssBytes: status.rssBytes,
      fdCount,
      service: shard.service,
      backendPort: shard.backendPort
    };
  });

  const memory = parseMeminfo(readFile('/proc/meminfo'));
  let disk = {
    totalBytes: 0,
    freeBytes: 0,
    inodesTotal: 0,
    inodesFree: 0
  };
  try {
    const stats = fs.statfsSync(dataDir);
    disk = {
      totalBytes: Number(stats.bsize) * Number(stats.blocks),
      freeBytes: Number(stats.bsize) * Number(stats.bavail),
      inodesTotal: Number(stats.files),
      inodesFree: Number(stats.ffree)
    };
  } catch (error) {
    failures.push({ code: 'statfs-failed', dataDir, error: error.message });
  }
  const input = {
    collectedAt: new Date().toISOString(),
    manifest: manifestPath,
    dataDir,
    host: {
      cpuCount: os.cpus().length,
      totalMemoryBytes: memory.totalMemoryBytes,
      freeMemoryBytes: memory.freeMemoryBytes,
      load1: os.loadavg()[0],
      disk
    },
    shards: rows
  };
  const audit = evaluateSingleCellCapacity(input, opts.policy || {});
  return {
    ok: failures.length === 0 && audit.ok,
    failures,
    input,
    audit
  };
}

module.exports = {
  expandManifestShards,
  parseMeminfo,
  parseProcStatus,
  collectSingleCellCapacity
};
