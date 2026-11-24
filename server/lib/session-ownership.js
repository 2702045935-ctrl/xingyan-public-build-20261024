'use strict';

class SessionOwnership {
  constructor(options) {
    const opts = options || {};
    this.defaultLeaseMs = Math.max(1000, Number(opts.defaultLeaseMs) || 90_000);
    this.now = typeof opts.now === 'function' ? opts.now : Date.now;
    this.claims = new Map();
    this.userIndex = new Map();
    this.epochs = new Map();
    this.claimed = 0;
    this.released = 0;
    this.expired = 0;
  }

  key(userId, connectionId) {
    return String(userId || '') + '|' + String(connectionId || '');
  }

  claim(userId, connectionId, gatewayId, options) {
    const uid = String(userId || '');
    const cid = String(connectionId || '');
    const gid = String(gatewayId || '');
    if (!uid || !cid || !gid) throw new Error('userId, connectionId and gatewayId are required');
    const now = this.now();
    const key = this.key(uid, cid);
    const existing = this.claims.get(key);
    if (existing && existing.expiresAt > now && existing.gatewayId !== gid
        && !(options && options.force === true)) {
      return { ok: false, reason: 'connection-owned', claim: Object.assign({}, existing) };
    }
    const epoch = Math.max(
      Number(this.epochs.get(uid) || 0),
      existing ? Number(existing.epoch) || 0 : 0
    ) + 1;
    this.epochs.set(uid, epoch);
    const claim = {
      userId: uid,
      connectionId: cid,
      gatewayId: gid,
      epoch,
      claimedAt: now,
      renewedAt: now,
      expiresAt: now + Math.max(1000, Number(options && options.leaseMs) || this.defaultLeaseMs)
    };
    this.claims.set(key, claim);
    if (!this.userIndex.has(uid)) this.userIndex.set(uid, new Set());
    this.userIndex.get(uid).add(key);
    this.claimed += 1;
    return { ok: true, claim: Object.assign({}, claim) };
  }

  lookupConnection(userId, connectionId) {
    const claim = this.claims.get(this.key(userId, connectionId));
    if (!claim) return null;
    if (claim.expiresAt <= this.now()) {
      this.remove(claim);
      return null;
    }
    return Object.assign({}, claim);
  }

  lookupUser(userId) {
    const keys = this.userIndex.get(String(userId || ''));
    if (!keys) return [];
    const rows = [];
    for (const key of Array.from(keys)) {
      const claim = this.claims.get(key);
      if (!claim) continue;
      if (claim.expiresAt <= this.now()) this.remove(claim);
      else rows.push(Object.assign({}, claim));
    }
    return rows;
  }

  renew(userId, connectionId, gatewayId, leaseMs) {
    const claim = this.claims.get(this.key(userId, connectionId));
    if (!claim || claim.gatewayId !== String(gatewayId || '')) return null;
    if (claim.expiresAt <= this.now()) {
      this.remove(claim);
      return null;
    }
    claim.renewedAt = this.now();
    claim.expiresAt = claim.renewedAt
      + Math.max(1000, Number(leaseMs) || this.defaultLeaseMs);
    return Object.assign({}, claim);
  }

  release(userId, connectionId, gatewayId, epoch) {
    const claim = this.claims.get(this.key(userId, connectionId));
    if (!claim) return false;
    if (gatewayId !== undefined && claim.gatewayId !== String(gatewayId || '')) return false;
    if (epoch !== undefined && Number(claim.epoch) !== Number(epoch)) return false;
    this.remove(claim);
    this.released += 1;
    return true;
  }

  remove(claim) {
    const key = this.key(claim.userId, claim.connectionId);
    this.claims.delete(key);
    const set = this.userIndex.get(claim.userId);
    if (!set) return;
    set.delete(key);
    if (!set.size) this.userIndex.delete(claim.userId);
    this.expired += 1;
  }

  reapExpired() {
    const now = this.now();
    let count = 0;
    for (const claim of Array.from(this.claims.values())) {
      if (claim.expiresAt <= now) {
        this.remove(claim);
        count += 1;
      }
    }
    return count;
  }

  snapshot() {
    return {
      claims: this.claims.size,
      users: this.userIndex.size,
      claimed: this.claimed,
      released: this.released,
      expired: this.expired,
      defaultLeaseMs: this.defaultLeaseMs
    };
  }
}

module.exports = { SessionOwnership };
