'use strict';

function ratio(used, total) {
  const t = Number(total);
  const u = Number(used);
  return t > 0 && Number.isFinite(u) ? Math.max(0, Math.min(1, u / t)) : 0;
}

function buildFleetMetrics(inputs, options) {
  const opts = options || {};
  const fdLimit = Math.max(1, Number(opts.fdLimit) || 65536);
  const cells = (Array.isArray(inputs) ? inputs : []).map((entry) => {
    const input = entry && entry.input && typeof entry.input === 'object'
      ? entry.input : entry;
    if (input && input.version === 2 && input.cell) {
      return Object.assign({}, input.cell, {
        id: String(entry.cellId || input.cell.id || '')
      });
    }
    const report = input.report || input;
    const capacity = report.input || report;
    const host = capacity.host || {};
    const disk = host.disk || {};
    const shards = Array.isArray(capacity.shards) ? capacity.shards : [];
    const maxFds = shards.reduce(
      (max, shard) => Math.max(max, Number(shard.fdCount) || 0),
      0
    );
    return {
      id: String(entry.cellId || capacity.cellId || opfsCellId(report) || ''),
      ok: report.ok !== false && capacity.ok !== false,
      memoryUsedRatio: ratio(
        Number(host.totalMemoryBytes) - Number(host.freeMemoryBytes),
        host.totalMemoryBytes
      ),
      loadPerCore: Number(host.cpuCount) > 0
        ? Math.max(0, Number(host.load1) || 0) / Number(host.cpuCount)
        : 0,
      fdUtilization: ratio(maxFds, fdLimit),
      p99Ms: Math.max(0, Number(entry.p99Ms ?? report.p99Ms) || 0),
      diskUsedRatio: ratio(
        Number(disk.totalBytes) - Number(disk.freeBytes),
        disk.totalBytes
      )
    };
  }).filter((cell) => cell.id);
  return {
    version: 1,
    generatedAt: new Date(Number(opts.now) || Date.now()).toISOString(),
    cells
  };
}

function opfsCellId(report) {
  return report && report.cellId ? report.cellId : '';
}

module.exports = { buildFleetMetrics };
