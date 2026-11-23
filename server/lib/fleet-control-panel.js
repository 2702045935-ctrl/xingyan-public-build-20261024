'use strict';

const fs = require('fs');
const path = require('path');

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(path.resolve(file), 'utf8'));
  } catch (_) {
    return null;
  }
}

function ageSeconds(file, now) {
  try {
    return Math.max(0,
      Math.round((Number(now || Date.now()) - fs.statSync(file).mtimeMs) / 1000));
  } catch (_) {
    return null;
  }
}

function tailJsonl(file, limit) {
  try {
    const rows = fs.readFileSync(path.resolve(file), 'utf8')
      .split(/\r?\n/).filter(Boolean);
    return rows.slice(-Math.max(1, Math.min(200, limit || 20))).map((line) => {
      try { return JSON.parse(line); }
      catch (_) { return { ok: false, error: 'invalid audit row' }; }
    });
  } catch (_) {
    return [];
  }
}

function controlStatus(inputs, now) {
  const cfg = inputs.config || {};
  const state = inputs.state || {};
  const metrics = inputs.metrics || null;
  const metricsAge = ageSeconds(inputs.metricsFile, now);
  const configAge = ageSeconds(inputs.configFile, now);
  const lockActive = inputs.lockActive === true;
  const execute = cfg.execute === true;
  const metricLimit = Math.max(10,
    Number(cfg.metricsMaxAgeSeconds) || 180);
  const metricsFresh = metricsAge != null && metricsAge <= metricLimit;
  const cells = Array.isArray(metrics && metrics.cells) ? metrics.cells : [];
  let status = 'disabled';
  if (lockActive) status = 'running';
  else if (execute && !metricsFresh) status = 'blocked-stale';
  else if (execute && cells.some((cell) => cell.ok === false)) status = 'degraded';
  else if (execute && cells.some((cell) =>
    Number(cell.memoryUsedRatio) >= 0.82
    || Number(cell.loadPerCore) >= 0.9
    || Number(cell.fdUtilization) >= 0.85
    || Number(cell.p99Ms) >= 2000
    || Number(cell.diskUsedRatio) >= 0.85)) status = 'pressured';
  else if (execute) status = 'healthy';
  return {
    version: 1,
    ok: true,
    status,
    execute,
    promoteOnSuccess: cfg.promoteOnSuccess === true,
    intervalSeconds: Number(cfg.intervalSeconds) || 60,
    configAgeSeconds: configAge,
    metricsAgeSeconds: metricsAge,
    metricsFresh,
    metricsLimitSeconds: metricLimit,
    lockActive,
    busy: state.busy === true,
    pressureStreak: Number(state.pressureStreak) || 0,
    lastCompletedAt: Number(state.lastCompletedAt) || 0,
    lastPlanFingerprint: String(state.lastPlanFingerprint || ''),
    lastResult: state.lastResult || null,
    generatedAt: metrics && metrics.generatedAt || '',
    cells
  };
}

function loadFleetControlPanel(options) {
  const opts = options || {};
  const configFile = opts.configFile
    || '/etc/xingyan-dual-cell/auto-scale.json';
  const stateFile = opts.stateFile
    || '/var/lib/xingyan-dual-cell/auto-scale-state.json';
  const metricsFile = opts.metricsFile
    || '/var/lib/xingyan-dual-cell/fleet-metrics.json';
  const auditFile = opts.auditFile
    || '/var/lib/xingyan-dual-cell/auto-scale-audit.jsonl';
  const lockFile = opts.lockFile || stateFile + '.lock';
  const config = readJson(configFile) || {};
  const state = readJson(stateFile) || {};
  const metrics = readJson(metricsFile);
  return {
    control: controlStatus({
      config,
      state,
      metrics,
      configFile,
      metricsFile,
      lockActive: fs.existsSync(lockFile)
    }, opts.now),
    recentAudit: tailJsonl(auditFile, Number(opts.auditLimit) || 20)
  };
}

module.exports = {
  controlStatus,
  loadFleetControlPanel,
  tailJsonl
};
