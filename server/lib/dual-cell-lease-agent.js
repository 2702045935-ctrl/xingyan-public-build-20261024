'use strict';

const { validateActiveDualCellPlan } = require('./dual-cell-active-plan');

class DualCellLeaseAgent {
  constructor(options) {
    const opts = options || {};
    const validated = opts.validatedPlan || validateActiveDualCellPlan(opts.plan);
    if (!validated.ok) {
      throw new Error('dual-cell plan is invalid: '
        + validated.failures.map((row) => row.code).join(','));
    }
    this.plan = validated.plan;
    this.cellKey = ['a', 'b'].find((key) =>
      key === opts.cell || validated.plan.cells[key].id === opts.cell);
    if (!this.cellKey) throw new Error('unknown dual-cell cell: ' + String(opts.cell || ''));
    this.cell = this.plan.cells[this.cellKey];
    this.leaseManager = opts.leaseManager;
    if (!this.leaseManager
        || typeof this.leaseManager.acquire !== 'function'
        || typeof this.leaseManager.renew !== 'function') {
      throw new Error('async leaseManager is required');
    }
    this.intervalMs = Math.max(500, Number(opts.intervalMs) || 5000);
    this.onLost = typeof opts.onLost === 'function' ? opts.onLost : () => {};
    this.active = false;
    this.lastError = '';
    this.timer = null;
    this.leases = new Map();
  }

  async start() {
    if (this.active) return this.status();
    const acquired = [];
    try {
      for (const shard of this.cell.ownedShards) {
        const lease = await this.leaseManager.acquire(shard);
        acquired.push(shard);
        this.leases.set(shard, lease);
      }
    } catch (error) {
      for (const shard of acquired) {
        try { await this.leaseManager.release(shard); } catch (_) { /* best effort */ }
      }
      this.lastError = String(error && error.message || error);
      throw error;
    }
    this.active = true;
    this.timer = setInterval(() => {
      this.renewOnce().catch((error) => {
        this.lastError = String(error && error.message || error);
      });
    }, this.intervalMs);
    if (this.timer.unref) this.timer.unref();
    return this.status();
  }

  async renewOnce() {
    if (!this.active) return this.status();
    let failed = null;
    for (const shard of Array.from(this.leases.keys())) {
      try {
        this.leases.set(shard, await this.leaseManager.renew(shard));
      } catch (error) {
        failed = { shard, error };
        break;
      }
    }
    if (failed) {
      this.active = false;
      if (this.timer) clearInterval(this.timer);
      this.timer = null;
      this.lastError = String(failed.error && failed.error.message || failed.error);
      this.onLost(failed);
      throw failed.error;
    }
    return this.status();
  }

  async takeoverAll() {
    if (!this.active) throw new Error('lease agent is not active');
    const acquired = [];
    for (let shard = 0; shard < this.plan.shardCount; shard += 1) {
      if (this.leases.has(shard)) continue;
      acquired.push(shard);
    }
    const results = [];
    for (const shard of acquired) {
      try {
        const lease = await this.leaseManager.acquire(shard);
        this.leases.set(shard, lease);
        results.push({ shard, epoch: lease.epoch });
      } catch (error) {
        for (const rollback of results) {
          try { await this.leaseManager.release(rollback.shard); } catch (_) { /* ignore */ }
          this.leases.delete(rollback.shard);
        }
        throw error;
      }
    }
    return results;
  }

  async stop() {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
    for (const shard of Array.from(this.leases.keys())) {
      try { await this.leaseManager.release(shard); } catch (_) { /* best effort */ }
    }
    this.leases.clear();
    this.active = false;
    return this.status();
  }

  status() {
    return {
      ok: this.active,
      cellId: this.cell.id,
      active: this.active,
      ownedShards: Array.from(this.leases.keys()).sort((a, b) => a - b),
      leases: Array.from(this.leases.entries()).map(([shard, lease]) => ({
        shard,
        epoch: Number(lease && lease.epoch) || 0
      })),
      lastError: this.lastError
    };
  }
}

module.exports = { DualCellLeaseAgent };
