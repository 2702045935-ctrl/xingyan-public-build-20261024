'use strict';

const fs = require('fs');
const path = require('path');
const {
  PhysicalAutoScaleController
} = require('./physical-auto-scale-controller');
const {
  createPhysicalScaleProductionAdapters
} = require('./physical-scale-production-adapters');
const { createSshRunner } = require('./physical-remote-runner');
const { validateFleetPlan } = require('./fleet-release-plan');
const { buildExpandedFleetPlan } = require('./physical-scale-target');

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

function stale(file, maxAgeMs, now) {
  const stat = fs.statSync(path.resolve(file));
  return Math.max(0, Number(now || Date.now()) - stat.mtimeMs) > maxAgeMs;
}

class PhysicalAutoScaleRuntime {
  constructor(options) {
    const opts = options || {};
    this.configFile = path.resolve(String(opts.configFile || ''));
    this.config = Object.assign({
      intervalSeconds: 60,
      metricsMaxAgeSeconds: 180,
      targetPlanMaxAgeSeconds: 86400,
      execute: false,
      promoteOnSuccess: false
    }, opts.config || readJson(this.configFile));
    if (!this.config.sourcePlanFile || !this.config.metricsFile
        || !this.config.stateFile || !this.config.auditFile) {
      throw new Error('runtime config is missing required paths');
    }
    if (this.config.targetPlanFile) {
      this.config.targetPlanFile = path.resolve(String(this.config.targetPlanFile));
    }
    this.controller = null;
    this.timer = null;
    this.adapterFactoryOverride = typeof opts.adapterFactory === 'function'
      ? opts.adapterFactory
      : null;
  }

  plan(file) {
    const value = readJson(file);
    const validation = validateFleetPlan(value);
    if (!validation.ok) throw new Error('fleet plan validation failed');
    return Object.assign({}, value, validation.normalized, {
      deploymentEligible: validation.deploymentEligible,
      warnings: validation.warnings
    });
  }

  metrics() {
    if (stale(this.config.metricsFile,
      Number(this.config.metricsMaxAgeSeconds) * 1000)) {
      throw new Error('fleet metrics are stale');
    }
    return readJson(this.config.metricsFile);
  }

  adapterFactory(source, target) {
    if (this.adapterFactoryOverride) {
      return this.adapterFactoryOverride(source, target);
    }
    const cfg = this.config;
    const routeFile = path.resolve(String(cfg.routePlanFile || ''));
    const routePlan = readJson(routeFile);
    return createPhysicalScaleProductionAdapters({
      sourcePlan: source,
      targetPlan: target,
      routePlan: {
        hash: String(routePlan.hash || ''),
        fileSha256: String(cfg.routePlanFileSha256 || ''),
        bytes: fs.readFileSync(routeFile)
      },
      routePlanFile: cfg.remoteRoutePlanFile || routeFile,
      secretFile: cfg.secretFile,
      gateway: cfg.gateway,
      remote: cfg.remote,
      runner: createSshRunner(cfg.ssh || {}),
      soakMinutes: cfg.soakMinutes || 30,
      minimumFreeBytes: cfg.minimumFreeBytes,
      minimumFreeInodes: cfg.minimumFreeInodes
    });
  }

  async runOnce() {
    const lockFile = path.resolve(this.config.lockFile
      || this.config.stateFile + '.lock');
    fs.mkdirSync(path.dirname(lockFile), { recursive: true });
    let lock;
    try {
      lock = fs.openSync(lockFile, 'wx', 0o600);
      fs.writeFileSync(lock, JSON.stringify({
        pid: process.pid,
        at: new Date().toISOString()
      }), 'utf8');
    } catch (error) {
      if (error && error.code === 'EEXIST') {
        const maxAge = Math.max(60,
          Number(this.config.lockMaxAgeSeconds) || 7200) * 1000;
        let staleLock = false;
        try {
          staleLock = Date.now() - fs.statSync(lockFile).mtimeMs > maxAge;
        } catch (_) { /* lock disappeared */ }
        if (!staleLock) return { ok: false, reason: 'scale-job-locked' };
        try { fs.unlinkSync(lockFile); } catch (_) { /* lost race */ }
        try {
          lock = fs.openSync(lockFile, 'wx', 0o600);
          fs.writeFileSync(lock, JSON.stringify({
            pid: process.pid,
            at: new Date().toISOString(),
            recovered: true
          }), 'utf8');
        } catch (_) {
          return { ok: false, reason: 'scale-job-locked' };
        }
      } else {
        throw error;
      }
    }
    try {
      return await this.runLocked();
    } finally {
      try { fs.closeSync(lock); } catch (_) { /* already closed */ }
      try { fs.unlinkSync(lockFile); } catch (_) { /* lock disappeared */ }
    }
  }

  async runLocked() {
    const source = this.plan(this.config.sourcePlanFile);
    let target;
    if (this.config.targetPlanFile) {
      if (stale(this.config.targetPlanFile,
        Number(this.config.targetPlanMaxAgeSeconds) * 1000)) {
        return { ok: false, reason: 'target-plan-stale' };
      }
      target = this.plan(this.config.targetPlanFile);
    } else if (this.config.expansion && this.config.expansion.additions) {
      target = buildExpandedFleetPlan(source, this.config.expansion.additions, {
        topologyId: this.config.expansion.topologyId,
        verifiedDomains: this.config.expansion.verifiedDomains
      });
    } else {
      return { ok: true, reason: 'target-plan-not-configured' };
    }
    if (!target.deploymentEligible) {
      return { ok: false, reason: 'target-plan-not-eligible', warnings: target.warnings };
    }
    if (!this.config.execute) {
      return { ok: false, reason: 'execution-disabled' };
    }
    this.controller = new PhysicalAutoScaleController({
      policy: this.config.policy,
      targetPlanFor: async () => target,
      adapterFactory: async (scalePlan) =>
        this.adapterFactory(source, target, scalePlan),
      loadState: async () => {
        try { return readJson(this.config.stateFile); } catch (_) { return {}; }
      },
      saveState: async (state) => atomicJson(this.config.stateFile, state)
    });
    await this.controller.init();
    const result = await this.controller.runOnce(source, this.metrics());
    const receipt = Object.assign({
      version: 1,
      at: new Date().toISOString(),
      sourceTopology: source.topologyId,
      targetTopology: target.topologyId,
      execute: true
    }, result);
    fs.mkdirSync(path.dirname(path.resolve(this.config.auditFile)), { recursive: true });
    fs.appendFileSync(path.resolve(this.config.auditFile),
      JSON.stringify(receipt) + '\n', 'utf8');
    if (result.ok && result.reason === 'complete' && this.config.promoteOnSuccess) {
      atomicJson(this.config.sourcePlanFile, target);
      atomicJson(this.config.stateFile, {
        pressureStreak: 0,
        busy: false,
        lastCompletedAt: Date.now(),
        lastPlanFingerprint: result.planFingerprint || '',
        lastResult: result
      });
    }
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
      Math.max(10, Number(this.config.intervalSeconds) || 60) * 1000);
    this.timer.unref();
  }

  stop() {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }
}

module.exports = {
  PhysicalAutoScaleRuntime,
  atomicJson,
  stale
};
