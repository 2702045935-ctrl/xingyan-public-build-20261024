'use strict';

const fs = require('fs');
const path = require('path');
const { PhysicalFailoverController } = require('./physical-failover-controller');
const {
  createPhysicalScaleProductionAdapters
} = require('./physical-scale-production-adapters');
const { createSshRunner } = require('./physical-remote-runner');
const { validateFleetPlan } = require('./fleet-release-plan');

function readJson(file) {
  return JSON.parse(fs.readFileSync(path.resolve(file), 'utf8'));
}

function atomicJson(file, value) {
  const target = path.resolve(file);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  const temporary = target + '.' + process.pid + '.tmp';
  fs.writeFileSync(temporary, JSON.stringify(value, null, 2) + '\n', 'utf8');
  fs.renameSync(temporary, target);
}

function appendJsonl(file, value) {
  const target = path.resolve(file);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.appendFileSync(target, JSON.stringify(value) + '\n', 'utf8');
}

function fresh(file, maxAgeMs, now) {
  try {
    return Math.max(0, Number(now || Date.now()) - fs.statSync(path.resolve(file)).mtimeMs)
      <= maxAgeMs;
  } catch (_) {
    return false;
  }
}

function fencingStatus(file, now) {
  try {
    const row = readJson(file);
    const at = Number(now || Date.now());
    const expiresAt = Number(row.expiresAt);
    if (row.ok !== true) return { ok: false, reason: 'fencing-not-ready' };
    if (row.quorum !== true) return { ok: false, reason: 'fencing-quorum-lost' };
    if (!Number.isSafeInteger(Number(row.epoch)) || Number(row.epoch) < 1) {
      return { ok: false, reason: 'fencing-epoch-invalid' };
    }
    if (!Number.isFinite(expiresAt) || expiresAt <= at) {
      return { ok: false, reason: 'fencing-expired' };
    }
    return {
      ok: true,
      epoch: Number(row.epoch),
      expiresAt,
      checkedAt: at
    };
  } catch (error) {
    if (error && error.code === 'ENOENT') {
      return { ok: false, reason: 'fencing-not-configured' };
    }
    return { ok: false, reason: 'fencing-read-failed' };
  }
}

class PhysicalFailoverRuntime {
  constructor(options) {
    const opts = options || {};
    this.configFile = path.resolve(String(opts.configFile || ''));
    this.config = Object.assign({
      enabled: false,
      execute: false,
      intervalSeconds: 30,
      metricsMaxAgeSeconds: 180,
      lockMaxAgeSeconds: 7200
    }, opts.config || readJson(this.configFile));
    if (!this.config.planFile || !this.config.metricsFile
        || !this.config.stateFile || !this.config.auditFile) {
      throw new Error('failover config is missing required paths');
    }
    this.timer = null;
    this.adapterFactoryOverride = typeof opts.adapterFactory === 'function'
      ? opts.adapterFactory : null;
    this.fencingOverride = typeof opts.fencingReady === 'function'
      ? opts.fencingReady : null;
  }

  plan() {
    const value = readJson(this.config.planFile);
    const validation = validateFleetPlan(value);
    if (!validation.ok) {
      const error = new Error('fleet plan validation failed');
      error.failures = validation.failures;
      throw error;
    }
    return Object.assign({}, value, validation.normalized, {
      deploymentEligible: validation.deploymentEligible,
      warnings: validation.warnings
    });
  }

  metrics() {
    if (!fresh(this.config.metricsFile,
      Math.max(10, Number(this.config.metricsMaxAgeSeconds) || 180) * 1000)) {
      throw new Error('fleet metrics are stale');
    }
    const metrics = readJson(this.config.metricsFile);
    if (!metrics || !Array.isArray(metrics.cells)) {
      throw new Error('fleet metrics are invalid');
    }
    return metrics;
  }

  fencingReady() {
    if (this.fencingOverride) return this.fencingOverride();
    const status = fencingStatus(this.config.fencingFile, Date.now());
    return status.ok;
  }

  adapterFactory(source, target) {
    if (this.adapterFactoryOverride) {
      return this.adapterFactoryOverride(source, target);
    }
    const cfg = this.config;
    const routePlan = readJson(cfg.routePlanFile);
    return createPhysicalScaleProductionAdapters({
      sourcePlan: source,
      targetPlan: target,
      routePlan: {
        hash: String(routePlan.hash || ''),
        fileSha256: String(cfg.routePlanFileSha256 || ''),
        bytes: fs.readFileSync(path.resolve(cfg.routePlanFile))
      },
      routePlanFile: cfg.remoteRoutePlanFile || cfg.routePlanFile,
      secretFile: cfg.secretFile,
      gateway: cfg.gateway,
      remote: cfg.remote,
      runner: createSshRunner(cfg.ssh || {}),
      provisioning: cfg.provisioning,
      soakMinutes: Math.max(1, Number(cfg.soakMinutes) || 1),
      minimumFreeBytes: cfg.minimumFreeBytes,
      minimumFreeInodes: cfg.minimumFreeInodes
    });
  }

  async runOnce() {
    const lockFile = path.resolve(this.config.lockFile
      || this.config.stateFile + '.lock');
    fs.mkdirSync(path.dirname(lockFile), { recursive: true });
    let lock = null;
    try {
      lock = fs.openSync(lockFile, 'wx', 0o600);
      fs.writeFileSync(lock, JSON.stringify({
        pid: process.pid,
        at: new Date().toISOString()
      }), 'utf8');
    } catch (error) {
      if (!error || error.code !== 'EEXIST') throw error;
      let staleLock = false;
      try {
        staleLock = Date.now() - fs.statSync(lockFile).mtimeMs
          > Math.max(60, Number(this.config.lockMaxAgeSeconds) || 7200) * 1000;
      } catch (_) { /* lock disappeared */ }
      if (!staleLock) return { ok: false, reason: 'failover-job-locked' };
      try { fs.unlinkSync(lockFile); } catch (_) { /* lost race */ }
      try {
        lock = fs.openSync(lockFile, 'wx', 0o600);
      } catch (_) {
        return { ok: false, reason: 'failover-job-locked' };
      }
    }
    try {
      return await this.runLocked();
    } finally {
      if (lock != null) {
        try { fs.closeSync(lock); } catch (_) { /* already closed */ }
      }
      try { fs.unlinkSync(lockFile); } catch (_) { /* lock disappeared */ }
    }
  }

  async runLocked() {
    if (this.config.enabled !== true || this.config.execute !== true) {
      return { ok: true, reason: 'execution-disabled' };
    }
    const baseline = this.plan();
    if (baseline.deploymentEligible !== true
        && this.config.allowUnverifiedDomains !== true) {
      return {
        ok: false,
        reason: 'fleet-not-production-eligible',
        warnings: baseline.warnings
      };
    }
    const controller = new PhysicalFailoverController({
      baselinePlan: baseline,
      policy: this.config.policy,
      fencingReady: () => this.fencingReady(),
      adapterFactory: (source, target) => this.adapterFactory(source, target),
      loadState: async () => {
        try { return readJson(this.config.stateFile); }
        catch (_) { return {}; }
      },
      saveState: async (state) => atomicJson(this.config.stateFile, state)
    });
    await controller.init();
    const result = await controller.runOnce(this.metrics());
    const receipt = Object.assign({
      version: 1,
      at: new Date().toISOString(),
      topologyId: baseline.topologyId,
      execute: true
    }, result);
    appendJsonl(this.config.auditFile, receipt);
    return receipt;
  }

  start(onResult) {
    if (this.timer) return;
    const tick = async () => {
      try {
        const result = await this.runOnce();
        if (typeof onResult === 'function') onResult(null, result);
      } catch (error) {
        if (typeof onResult === 'function') onResult(error, null);
      }
    };
    tick();
    this.timer = setInterval(tick,
      Math.max(5, Number(this.config.intervalSeconds) || 30) * 1000);
    this.timer.unref();
  }

  stop() {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }
}

module.exports = {
  PhysicalFailoverRuntime,
  appendJsonl,
  atomicJson,
  fencingStatus,
  fresh
};
