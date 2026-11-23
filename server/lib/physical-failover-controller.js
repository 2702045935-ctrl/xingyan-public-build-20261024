'use strict';

const { validateFleetPlan } = require('./fleet-release-plan');

const DEFAULT_POLICY = Object.freeze({
  failureSamples: 3,
  recoverySamples: 6,
  failbackCooldownSeconds: 300,
  soakSeconds: 60
});

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function buildFailoverPlan(sourcePlan, unhealthyCellIds, policy) {
  const source = clone(sourcePlan);
  const validation = validateFleetPlan(source);
  if (!validation.ok) {
    return { ok: false, reason: 'source-plan-invalid', failures: validation.failures };
  }
  const unhealthy = new Set(unhealthyCellIds.map(String));
  const target = clone(source);
  target.topologyId = source.topologyId + '-failover';
  const owners = new Map(target.cells.map((cell) => [cell.id, 0]));
  target.cells.forEach((cell) => {
    owners.set(cell.id, cell.ownerShards.length);
  });
  const moves = [];
  for (let shard = 0; shard < target.shardCount; shard += 1) {
    const owner = target.cells.find((cell) => cell.ownerShards.includes(shard));
    if (!owner || !unhealthy.has(owner.id)) continue;
    const candidates = target.cells
      .filter((cell) => !unhealthy.has(cell.id)
        && cell.replicaShards.includes(shard))
      .sort((left, right) =>
        owners.get(left.id) - owners.get(right.id)
        || left.id.localeCompare(right.id));
    if (!candidates.length) {
      return { ok: false, reason: 'no-healthy-replica', shard };
    }
    const replacement = candidates[0];
    owner.ownerShards = owner.ownerShards.filter((value) => value !== shard);
    replacement.ownerShards.push(shard);
    replacement.ownerShards.sort((a, b) => a - b);
    owners.set(owner.id, owners.get(owner.id) - 1);
    owners.set(replacement.id, owners.get(replacement.id) + 1);
    moves.push({
      shard,
      fromCellId: owner.id,
      toCellId: replacement.id,
      fromHost: owner.host,
      toHost: replacement.host
    });
  }
  target.policy = Object.assign({}, target.policy, {
    failover: {
      minHealthyReplicas: Number(policy && policy.minHealthyReplicas) || 1,
      fencingRequired: true
    }
  });
  const targetValidation = validateFleetPlan(target);
  if (!targetValidation.ok) {
    return {
      ok: false,
      reason: 'target-plan-invalid',
      failures: targetValidation.failures
    };
  }
  return {
    ok: moves.length > 0,
    reason: moves.length ? 'failover-required' : 'no-owner-impact',
    sourcePlan: source,
    targetPlan: target,
    moves,
    unhealthyCellIds: Array.from(unhealthy)
  };
}

function buildFailbackPlan(activePlan, baselinePlan) {
  const active = clone(activePlan);
  const baseline = clone(baselinePlan);
  const activeValidation = validateFleetPlan(active);
  const baselineValidation = validateFleetPlan(baseline);
  if (!activeValidation.ok || !baselineValidation.ok) {
    return {
      ok: false,
      reason: 'failback-plan-invalid',
      failures: [
        ...activeValidation.failures.map((row) =>
          Object.assign({}, row, { detail: 'active: ' + row.detail })),
        ...baselineValidation.failures.map((row) =>
          Object.assign({}, row, { detail: 'baseline: ' + row.detail }))
      ]
    };
  }
  if (activeValidation.normalized.shardCount
      !== baselineValidation.normalized.shardCount) {
    return { ok: false, reason: 'failback-shard-count-mismatch' };
  }
  const activeCellByShard = new Map();
  const baselineCellByShard = new Map();
  activeValidation.normalized.cells.forEach((cell) => {
    cell.ownerShards.forEach((shard) => activeCellByShard.set(shard, cell));
  });
  baselineValidation.normalized.cells.forEach((cell) => {
    cell.ownerShards.forEach((shard) => baselineCellByShard.set(shard, cell));
  });
  const moves = [];
  for (let shard = 0; shard < baselineValidation.normalized.shardCount; shard += 1) {
    const activeOwner = activeCellByShard.get(shard);
    const baselineOwner = baselineCellByShard.get(shard);
    if (!activeOwner || !baselineOwner) {
      return { ok: false, reason: 'failback-owner-missing', shard };
    }
    if (activeOwner.id === baselineOwner.id) continue;
    moves.push({
      shard,
      fromCellId: activeOwner.id,
      toCellId: baselineOwner.id,
      fromHost: activeOwner.host,
      toHost: baselineOwner.host
    });
  }
  return {
    ok: moves.length > 0,
    reason: moves.length ? 'failback-required' : 'already-at-baseline',
    sourcePlan: active,
    targetPlan: baseline,
    moves
  };
}

async function attempt(adapter, operation, retries) {
  let last;
  for (let index = 0; index < Math.max(1, retries || 1); index += 1) {
    try {
      return await adapter(operation);
    } catch (error) {
      last = error;
      if (index + 1 < Math.max(1, retries || 1)) {
        await new Promise((resolve) => setTimeout(resolve, 100));
      }
    }
  }
  throw last;
}

async function executeFailover(plan, adapters, options) {
  const retries = Math.max(1, Number(options && options.retries) || 1);
  const events = [];
  const record = (phase, move, extra) => events.push(Object.assign({
    at: new Date().toISOString(),
    phase,
    shard: move && move.shard,
    fromCellId: move && move.fromCellId,
    toCellId: move && move.toCellId
  }, extra || {}));
  for (const move of plan.moves) {
    let leaseAcquired = false;
    let routesSwitched = false;
    let gatewaySwitched = false;
    let replicationSwitched = false;
    try {
      record('replica-catch-up', move);
      await attempt(adapters.waitReplicaCaughtUp, move, retries);
      record('shadow-read', move);
      await attempt(adapters.shadowRead, move, retries);
      record('acquire-lease', move);
      await attempt(adapters.acquireLease, move, retries);
      leaseAcquired = true;
      record('switch-routes', move);
      await attempt(adapters.switchRoutes, move, retries);
      routesSwitched = true;
      record('switch-gateway', move);
      await attempt(adapters.switchGateway, move, retries);
      gatewaySwitched = true;
      record('unfreeze-target', move);
      await attempt(adapters.unfreezeOwner, move, retries);
      record('verify-owner', move);
      await attempt(adapters.verifyOwner, move, retries);
      record('switch-replication', move);
      await attempt(adapters.switchReplication, move, retries);
      replicationSwitched = true;
      record('complete', move);
    } catch (error) {
      record('failed', move, { reason: error.message });
      try {
        if (replicationSwitched) {
          await adapters.switchReplication(Object.assign({}, move, { rollback: true }));
        }
        if (routesSwitched) {
          await adapters.switchRoutes(Object.assign({}, move, { rollback: true }));
        }
        if (gatewaySwitched || routesSwitched) {
          await adapters.switchGateway(Object.assign({}, move, { rollback: true }));
        }
        if (leaseAcquired) {
          await adapters.acquireLease(Object.assign({}, move, { rollback: true }));
        }
        record('rollback-complete', move);
      } catch (rollbackError) {
        record('rollback-failed', move, { reason: rollbackError.message });
        return { ok: false, reason: 'rollback-failed', events };
      }
      return { ok: false, reason: 'failover-failed', shard: move.shard, events };
    }
  }
  if (typeof adapters.soak === 'function') {
    record('soak');
    await adapters.soak(plan);
  }
  return { ok: true, reason: 'complete', events };
}

class PhysicalFailoverController {
  constructor(options) {
    const opts = options || {};
    this.policy = Object.assign({}, DEFAULT_POLICY, opts.policy || {});
    this.now = typeof opts.now === 'function' ? opts.now : () => Date.now();
    this.adapterFactory = opts.adapterFactory;
    this.fencingReady = opts.fencingReady || (async () => false);
    this.loadState = opts.loadState || (async () => ({}));
    this.saveState = opts.saveState || (async () => {});
    this.baselinePlan = opts.baselinePlan;
    this.state = {
      mode: 'normal',
      busy: false,
      failureStreak: {},
      recoveryStreak: {},
      failedOverAt: 0,
      failedCellIds: [],
      activePlan: opts.baselinePlan || null,
      lastResult: null,
      lastTransitionAt: 0,
      transitionCount: 0
    };
  }

  async init() {
    const saved = await this.loadState();
    if (saved && typeof saved === 'object') {
      this.state = Object.assign(this.state, saved);
    }
    this.state.busy = false;
  }

  async persist() {
    await this.saveState(Object.assign({}, this.state));
  }

  healthy(metrics, cellId) {
    const cell = (metrics.cells || []).find((row) => row.id === cellId);
    return !!cell && cell.ok !== false;
  }

  updateCounters(metrics) {
    const plan = this.state.activePlan || this.baselinePlan;
    if (!plan || !Array.isArray(plan.cells)) return;
    for (const cell of plan.cells) {
      const healthy = this.healthy(metrics, cell.id);
      if (healthy) {
        this.state.recoveryStreak[cell.id] =
          (Number(this.state.recoveryStreak[cell.id]) || 0) + 1;
        this.state.failureStreak[cell.id] = 0;
      } else {
        this.state.failureStreak[cell.id] =
          (Number(this.state.failureStreak[cell.id]) || 0) + 1;
        this.state.recoveryStreak[cell.id] = 0;
      }
    }
  }

  async fencingState() {
    try {
      const value = await this.fencingReady();
      return value === true
        ? { ok: true }
        : { ok: false, reason: 'fencing-not-ready' };
    } catch (error) {
      return {
        ok: false,
        reason: 'fencing-check-failed',
        error: String(error && error.message || error)
      };
    }
  }

  async execute(plan) {
    this.state.busy = true;
    await this.persist();
    try {
      const adapters = await this.adapterFactory(plan.sourcePlan, plan.targetPlan);
      return await executeFailover(plan, adapters, {
        retries: this.policy.retries || 1
      });
    } catch (error) {
      return {
        ok: false,
        reason: 'failover-execution-error',
        error: String(error && error.message || error),
        events: []
      };
    } finally {
      this.state.busy = false;
    }
  }

  async failover(failed) {
    const plan = buildFailoverPlan(this.state.activePlan, failed, this.policy);
    if (!plan.ok) {
      this.state.lastResult = plan;
      await this.persist();
      return plan;
    }
    const fencing = await this.fencingState();
    if (!fencing.ok) {
      this.state.lastResult = fencing;
      await this.persist();
      return fencing;
    }
    const result = await this.execute(plan);
    this.state.lastResult = result;
    if (result.ok) {
      const failedCells = Array.from(new Set(plan.moves.map((move) =>
        move.fromCellId)));
      this.state.mode = 'failed-over';
      this.state.activePlan = plan.targetPlan;
      this.state.failedOverAt = this.now();
      this.state.failedCellIds = failedCells;
      this.state.lastTransitionAt = this.now();
      this.state.transitionCount = Number(this.state.transitionCount || 0) + 1;
      this.state.failureStreak = {};
      this.state.recoveryStreak = {};
    }
    await this.persist();
    return result;
  }

  async failback() {
    const failedCells = Array.isArray(this.state.failedCellIds)
      ? this.state.failedCellIds
      : [];
    if (!failedCells.length) {
      await this.persist();
      return { ok: true, reason: 'waiting-failback' };
    }
    const waiting = failedCells.filter((cellId) =>
      Number(this.state.recoveryStreak[cellId]) < this.policy.recoverySamples);
    if (waiting.length) {
      await this.persist();
      return {
        ok: true,
        reason: 'waiting-failback',
        waitingCellIds: waiting
      };
    }
    const cooled = this.now() - Number(this.state.failedOverAt || 0)
      >= this.policy.failbackCooldownSeconds * 1000;
    if (!cooled) {
      await this.persist();
      return { ok: true, reason: 'waiting-failback' };
    }
    const plan = buildFailbackPlan(this.state.activePlan, this.baselinePlan);
    if (!plan.ok) {
      this.state.lastResult = plan;
      await this.persist();
      return plan;
    }
    const fencing = await this.fencingState();
    if (!fencing.ok) {
      this.state.lastResult = fencing;
      await this.persist();
      return fencing;
    }
    const result = await this.execute(plan);
    this.state.lastResult = result;
    if (result.ok) {
      this.state.mode = 'normal';
      this.state.activePlan = plan.targetPlan;
      this.state.failedOverAt = 0;
      this.state.failedCellIds = [];
      this.state.failureStreak = {};
      this.state.recoveryStreak = {};
      this.state.lastTransitionAt = this.now();
      this.state.transitionCount = Number(this.state.transitionCount || 0) + 1;
    }
    await this.persist();
    return result;
  }

  async runOnce(metrics) {
    if (this.state.busy) return { ok: false, reason: 'failover-in-progress' };
    this.updateCounters(metrics);
    const failed = Object.keys(this.state.failureStreak).filter((id) =>
      Number(this.state.failureStreak[id]) >= this.policy.failureSamples);
    if (this.state.mode === 'normal') {
      if (!failed.length) {
        await this.persist();
        return { ok: true, reason: 'healthy' };
      }
      return this.failover(failed);
    }

    const failedCellIds = Array.isArray(this.state.failedCellIds)
      ? this.state.failedCellIds : [];
    if (!failedCellIds.length) {
      await this.persist();
      return { ok: true, reason: 'failed-owner-quarantined' };
    }
    return this.failback();
  }
}

module.exports = {
  DEFAULT_POLICY,
  buildFailoverPlan,
  buildFailbackPlan,
  executeFailover,
  PhysicalFailoverController
};
