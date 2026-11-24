'use strict';

const crypto = require('crypto');

function int(value, fallback) {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : fallback;
}

class ConnectionGovernor {
  constructor(options) {
    const opts = options || {};
    this.maxTotal = int(opts.maxTotal, 100_000);
    this.maxPerUser = int(opts.maxPerUser, 4);
    this.maxPerIp = int(opts.maxPerIp, 120);
    this.softLoadRatio = Math.max(0.1, Math.min(1, Number(opts.softLoadRatio) || 0.85));
    this.now = typeof opts.now === 'function' ? opts.now : Date.now;
    this.uid = typeof opts.uid === 'function'
      ? opts.uid
      : () => `conn_${crypto.randomBytes(10).toString('hex')}`;
    this.draining = false;
    this.total = 0;
    this.byUser = new Map();
    this.byIp = new Map();
    this.leases = new Map();
    this.accepted = 0;
    this.rejected = 0;
    this.released = 0;
    this.rejectReasons = Object.create(null);
  }

  loadRatio() {
    return this.maxTotal <= 0 ? 1 : this.total / this.maxTotal;
  }

  isSaturated() {
    return this.total >= this.maxTotal;
  }

  isSoftLoaded() {
    return this.loadRatio() >= this.softLoadRatio;
  }

  reject(reason) {
    this.rejected += 1;
    this.rejectReasons[reason] = (this.rejectReasons[reason] || 0) + 1;
    return {
      ok: false,
      reason,
      retryAfterMs: reason === 'draining' ? 1000 : 250,
      snapshot: this.snapshot()
    };
  }

  admit(input) {
    const row = input || {};
    const userId = String(row.userId || '');
    const ip = String(row.ip || '');
    if (this.draining) return this.reject('draining');
    if (this.isSaturated()) return this.reject('capacity');
    if (!userId) return this.reject('missing-user');
    if (this.byUser.get(userId) >= this.maxPerUser) return this.reject('user-limit');
    if (ip && this.byIp.get(ip) >= this.maxPerIp) return this.reject('ip-limit');

    const lease = {
      id: this.uid('ws'),
      userId,
      ip,
      kind: String(row.kind || 'phone'),
      deviceId: String(row.deviceId || ''),
      admittedAt: this.now(),
      releasedAt: 0
    };
    this.leases.set(lease.id, lease);
    this.total += 1;
    this.accepted += 1;
    this.byUser.set(userId, (this.byUser.get(userId) || 0) + 1);
    if (ip) this.byIp.set(ip, (this.byIp.get(ip) || 0) + 1);
    return {
      ok: true,
      lease,
      snapshot: this.snapshot()
    };
  }

  release(leaseOrId) {
    const id = typeof leaseOrId === 'string'
      ? leaseOrId
      : leaseOrId && leaseOrId.id;
    const lease = id ? this.leases.get(id) : null;
    if (!lease) return false;
    this.leases.delete(id);
    this.total = Math.max(0, this.total - 1);
    this.released += 1;
    const userCount = (this.byUser.get(lease.userId) || 1) - 1;
    if (userCount > 0) this.byUser.set(lease.userId, userCount);
    else this.byUser.delete(lease.userId);
    if (lease.ip) {
      const ipCount = (this.byIp.get(lease.ip) || 1) - 1;
      if (ipCount > 0) this.byIp.set(lease.ip, ipCount);
      else this.byIp.delete(lease.ip);
    }
    lease.releasedAt = this.now();
    return true;
  }

  drain() {
    this.draining = true;
    return this.snapshot();
  }

  resume() {
    this.draining = false;
    return this.snapshot();
  }

  snapshot() {
    return {
      draining: this.draining,
      total: this.total,
      maxTotal: this.maxTotal,
      loadRatio: Math.round(this.loadRatio() * 10000) / 10000,
      softLoadRatio: this.softLoadRatio,
      saturated: this.isSaturated(),
      softLoaded: this.isSoftLoaded(),
      uniqueUsers: this.byUser.size,
      uniqueIps: this.byIp.size,
      accepted: this.accepted,
      rejected: this.rejected,
      released: this.released,
      rejectReasons: Object.assign({}, this.rejectReasons),
      maxPerUser: this.maxPerUser,
      maxPerIp: this.maxPerIp
    };
  }
}

module.exports = { ConnectionGovernor };
