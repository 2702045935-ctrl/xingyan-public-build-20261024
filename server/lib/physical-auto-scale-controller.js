'use strict';

const { buildPhysicalScalePlan } = require('./physical-scale-plan');
const { executePhysicalScale } = require('./physical-scale-orchestrator');

const DEFAULT_POLICY = Object.freeze({
  windowSamples: 3,
  minimumSignals: 2,
  maxMemoryUsedRatio: 0.82,
  maxLoadPerCore: 0.90,
  maxFdUtilization: 0.85,
  maxP99Ms: 2000,
  maxDiskUsedRatio: 0.85,
  cooldownMinutes: 60
});

function number(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function evaluatePressure(metrics, policyInput) {
  const policy = Object.assign({}, DEFAULT_POLICY, policyInput || {});
  const cells = Array.isArray(metrics && metrics.cells) ? metrics.cells : [];
  const rows = cells.map((cell) => {
    const signals = [];
    if (number(cell.memoryUsedRatio) > policy.maxMemoryUsedRatio) {
      signals.push('memory');
    }
    if (number(cell.loadPerCore) > policy.maxLoadPerCore) {
      signals.push('cpu');
    }
    if (number(cell.fdUtilization) > policy.maxFdUtilization) {
      signals.push('fds');
    }
    if (number(cell.p99Ms) > policy.maxP99Ms) {
      signals.push('latency');
    }
    if (number(cell.diskUsedRatio) > policy.maxDiskUsedRatio) {
      signals.push('disk');
    }
    return {
      cellId: String(cell.id || ''),
      healthy: cell.ok !== false,
      signals,
      pressured: cell.ok !== false && signals.length >= policy.minimumSignals
    };
  });
  return {
    pressured: rows.some((row) => row.pressured),
    cells: rows
  };
}

class PhysicalAutoScaleController {
  constructor(options) {
    const opts = options || {};
    this.policy = Object.assign({}, DEFAULT_POLICY, opts.policy || {});
    this.adapters = opts.adapters || {};
    this.adapterFactory = typeof opts.adapterFactory === 'function'
      ? opts.adapterFactory
      : null;
    this.targetPlanFor = opts.targetPlanFor;
    this.now = typeof opts.now === 'function' ? opts.now : () => Date.now();
    this.loadState = typeof opts.loadState === 'function'
      ? opts.loadState
      : async () => ({});
    this.saveState = typeof opts.saveState === 'function'
      ? opts.saveState
      : async () => {};
    this.state = {
      pressureStreak: 0,
      busy: false,
      lastCompletedAt: 0,
      lastPlanFingerprint: '',
      lastResult: null
    };
  }

  async init() {
    const loaded = await this.loadState();
    if (loaded && typeof loaded === 'object') {
      this.state = Object.assign(this.state, loaded);
    }
    this.state.busy = false;
  }

  async persist() {
    await this.saveState(Object.assign({}, this.state));
  }

  async runOnce(sourcePlan, metrics) {
    if (this.state.busy) {
      return { ok: false, reason: 'scale-job-in-progress' };
    }
    const pressure = evaluatePressure(metrics, this.policy);
    if (!pressure.pressured) {
      this.state.pressureStreak = 0;
      await this.persist();
      return { ok: true, reason: 'capacity-normal', pressure };
    }
    const current = this.now();
    const cooldownMs = this.policy.cooldownMinutes * 60 * 1000;
    const lastCompletedAt = Number(this.state.lastCompletedAt || 0);
    if (lastCompletedAt > 0 && current - lastCompletedAt < cooldownMs) {
      await this.persist();
      return { ok: true, reason: 'cooldown', pressure };
    }
    this.state.pressureStreak = Math.max(0, Number(this.state.pressureStreak) || 0) + 1;
    if (this.state.pressureStreak < this.policy.windowSamples) {
      await this.persist();
      return {
        ok: true,
        reason: 'pressure-warming',
        streak: this.state.pressureStreak,
        pressure
      };
    }
    if (typeof this.targetPlanFor !== 'function') {
      this.state.lastResult = { ok: false, reason: 'target-plan-provider-missing' };
      await this.persist();
      return this.state.lastResult;
    }
    const targetPlan = await this.targetPlanFor(sourcePlan, pressure);
    const scalePlan = buildPhysicalScalePlan(sourcePlan, targetPlan, {
      maxShardMoves: targetPlan && targetPlan.shardCount,
      soakMinutes: this.policy.soakMinutes || 30
    });
    if (!scalePlan.ok) {
      this.state.lastResult = {
        ok: false,
        reason: 'scale-plan-invalid',
        failures: scalePlan.failures
      };
      await this.persist();
      return this.state.lastResult;
    }

    this.state.busy = true;
    this.state.lastPlanFingerprint = scalePlan.fingerprint;
    await this.persist();
    let result;
    try {
      const adapters = this.adapterFactory
        ? await this.adapterFactory(scalePlan, targetPlan)
        : this.adapters;
      result = await executePhysicalScale(scalePlan, adapters, {
        retries: this.policy.retries || 2
      });
    } catch (error) {
      result = {
        version: 1,
        ok: false,
        reason: 'scale-execution-error',
        error: String(error && error.message || error)
      };
    }
    this.state.busy = false;
    this.state.lastResult = result;
    if (result.ok) {
      this.state.lastCompletedAt = current;
      this.state.pressureStreak = 0;
    }
    await this.persist();
    return Object.assign({ planFingerprint: scalePlan.fingerprint }, result);
  }
}

module.exports = {
  DEFAULT_POLICY,
  evaluatePressure,
  PhysicalAutoScaleController
};
