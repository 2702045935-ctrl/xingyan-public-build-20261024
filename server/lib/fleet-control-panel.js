'use strict';

const fs = require('fs');
const path = require('path');
const { validateFleetPlan } = require('./fleet-release-plan');

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

function fencingPanelStatus(config, now) {
  const file = config && config.fencingFile;
  if (!file) {
    return {
      configured: false,
      ready: false,
      reason: 'fencing-not-configured'
    };
  }
  const row = readJson(file);
  if (!row) {
    return { configured: true, ready: false, reason: 'fencing-status-missing' };
  }
  const at = Number(now || Date.now());
  const expiresAt = Number(row.expiresAt);
  const ready = row.ok === true
    && row.quorum === true
    && Number.isSafeInteger(Number(row.epoch))
    && Number(row.epoch) > 0
    && Number.isFinite(expiresAt)
    && expiresAt > at;
  return {
    configured: true,
    ready,
    reason: ready ? 'ready'
      : row.quorum !== true ? 'fencing-quorum-lost'
        : !Number.isFinite(expiresAt) || expiresAt <= at
          ? 'fencing-expired'
          : 'fencing-not-ready',
    epoch: Number(row.epoch) || 0,
    expiresAt: Number(expiresAt) || 0,
    checkedAt: at
  };
}

function failoverStatus(config, state, fencing, now) {
  const activePlan = state.activePlan || null;
  const activeValidation = activePlan ? validateFleetPlan(activePlan) : null;
  const failedCellIds = Array.isArray(state.failedCellIds)
    ? state.failedCellIds.map(String) : [];
  const mode = ['normal', 'failed-over'].includes(state.mode)
    ? state.mode : 'normal';
  const enabled = config.enabled === true;
  const execute = config.execute === true;
  const blockers = [];
  if (!enabled) blockers.push('self-healing-disabled');
  if (!execute) blockers.push('execution-disabled');
  if (enabled && !fencing.ready) blockers.push(fencing.reason);
  return {
    version: 1,
    ok: true,
    status: !enabled ? 'disabled'
      : mode === 'failed-over' ? 'failed-over'
        : !fencing.ready ? 'blocked-fencing'
          : execute ? 'healthy' : 'observe-only',
    enabled,
    execute,
    mode,
    busy: state.busy === true,
    fencing,
    blockers,
    failedCellIds,
    failedOverAt: Number(state.failedOverAt) || 0,
    lastTransitionAt: Number(state.lastTransitionAt) || 0,
    transitionCount: Number(state.transitionCount) || 0,
    failureStreak: state.failureStreak || {},
    recoveryStreak: state.recoveryStreak || {},
    activeTopologyId: activeValidation && activeValidation.ok
      ? activeValidation.normalized.topologyId : '',
    activeCellCount: activeValidation && activeValidation.ok
      ? activeValidation.normalized.cells.length : 0,
    activePlanValid: !!activeValidation && activeValidation.ok,
    lastResult: state.lastResult || null,
    checkedAt: Number(now) || Date.now()
  };
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
  const failoverConfigFile = opts.failoverConfigFile
    || '/etc/xingyan-dual-cell/failover.json';
  const failoverStateFile = opts.failoverStateFile
    || '/var/lib/xingyan-dual-cell/failover-state.json';
  const failoverAuditFile = opts.failoverAuditFile
    || '/var/lib/xingyan-dual-cell/failover-audit.jsonl';
  const lockFile = opts.lockFile || stateFile + '.lock';
  const config = readJson(configFile) || {};
  const state = readJson(stateFile) || {};
  const failoverConfig = readJson(failoverConfigFile) || {};
  const failoverState = readJson(failoverStateFile) || {};
  const metrics = readJson(metricsFile);
  const sourcePlan = readJson(config.sourcePlanFile);
  const targetPlan = readJson(config.targetPlanFile);
  const sourceValidation = sourcePlan ? validateFleetPlan(sourcePlan) : null;
  const targetValidation = targetPlan ? validateFleetPlan(targetPlan) : null;
  return {
    control: controlStatus({
      config,
      state,
      metrics,
      configFile,
      metricsFile,
      lockActive: fs.existsSync(lockFile)
    }, opts.now),
    recentAudit: tailJsonl(auditFile, Number(opts.auditLimit) || 20),
    migration: {
      sourceTopology: sourceValidation && sourceValidation.ok
        ? sourceValidation.normalized.topologyId : '',
      targetTopology: targetValidation && targetValidation.ok
        ? targetValidation.normalized.topologyId : '',
      sourceCellCount: sourceValidation && sourceValidation.ok
        ? sourceValidation.normalized.cells.length : 0,
      targetCellCount: targetValidation && targetValidation.ok
        ? targetValidation.normalized.cells.length : 0,
      shardCount: targetValidation && targetValidation.ok
        ? targetValidation.normalized.shardCount : 0,
      targetValid: !!targetValidation && targetValidation.ok,
      targetEligible: !!targetValidation
        && targetValidation.deploymentEligible,
      targetWarnings: targetValidation ? targetValidation.warnings : [],
      targetFailures: targetValidation ? targetValidation.failures : [],
      lastResult: state.lastResult || null
    },
    selfHealing: Object.assign(
      failoverStatus(
        failoverConfig,
        failoverState,
        fencingPanelStatus(failoverConfig, opts.now),
        opts.now
      ),
      {
        recentAudit: tailJsonl(failoverAuditFile,
          Number(opts.failoverAuditLimit) || 20),
        baselineTopology: sourceValidation && sourceValidation.ok
          ? sourceValidation.normalized.topologyId : ''
      }
    )
  };
}

module.exports = {
  controlStatus,
  failoverStatus,
  fencingPanelStatus,
  loadFleetControlPanel,
  tailJsonl
};
