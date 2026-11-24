'use strict';

const crypto = require('crypto');

function text(value, max) {
  return String(value == null ? '' : value).slice(0, max);
}

function number(value, fallback) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function hash32(value) {
  return crypto.createHash('sha256').update(String(value)).digest().readUInt32BE(0);
}

class GatewayDirectory {
  constructor(options) {
    const opts = options || {};
    this.nodeTimeoutMs = Math.max(1000, number(opts.nodeTimeoutMs, 30_000));
    this.defaultLeaseMs = Math.max(1000, number(opts.defaultLeaseMs, 90_000));
    this.now = typeof opts.now === 'function' ? opts.now : Date.now;
    this.nodes = new Map();
    this.claims = new Map();
    this.epochs = new Map();
    this.registered = 0;
    this.claimed = 0;
    this.released = 0;
    this.expired = 0;
  }

  register(input) {
    const row = input || {};
    const id = text(row.id, 120);
    if (!id) throw new Error('gateway node id is required');
    const capacity = Math.max(1, Math.floor(number(row.capacity, 100_000)));
    const node = {
      id,
      endpoint: text(row.endpoint, 500),
      cellId: text(row.cellId, 120),
      failureDomain: text(row.failureDomain, 160),
      capacity,
      weight: Math.max(0.01, number(row.weight, 1)),
      active: row.active !== false,
      draining: row.draining === true,
      connections: Math.max(0, Math.floor(number(row.connections, 0))),
      lastHeartbeat: number(row.lastHeartbeat, this.now()),
      startedAt: number(row.startedAt, this.now())
    };
    this.nodes.set(id, node);
    this.registered += 1;
    return Object.assign({}, node);
  }

  heartbeat(id, input) {
    const node = this.nodes.get(text(id, 120));
    if (!node) throw new Error('gateway node is not registered');
    const row = input || {};
    node.connections = Math.max(0, Math.floor(number(row.connections, node.connections)));
    node.capacity = Math.max(1, Math.floor(number(row.capacity, node.capacity)));
    node.lastHeartbeat = number(row.lastHeartbeat, this.now());
    node.draining = row.draining === true;
    node.active = row.active !== false;
    return Object.assign({}, node);
  }

  unregister(id) {
    return this.nodes.delete(text(id, 120));
  }

  liveNodes() {
    const now = this.now();
    return Array.from(this.nodes.values()).filter((node) =>
      node.active &&
      !node.draining &&
      node.capacity > 0 &&
      now - node.lastHeartbeat <= this.nodeTimeoutMs
    );
  }

  pick(userId, options) {
    const opts = options || {};
    const excluded = new Set((opts.exclude || []).map((value) => String(value)));
    const candidates = this.liveNodes().filter((node) => !excluded.has(node.id));
    if (!candidates.length) return null;
    const key = String(userId || '');
    const scored = candidates.map((node) => {
      const load = node.connections / Math.max(1, node.capacity);
      const hash = hash32(node.id + '|' + key);
      const rendezvous = 1 - (hash / 0xFFFFFFFF);
      const score = rendezvous * node.weight - load * 0.75;
      return { node, score, load };
    }).sort((a, b) => b.score - a.score);
    const selected = scored[0];
    return {
      node: Object.assign({}, selected.node),
      load: Math.round(selected.load * 10000) / 10000
    };
  }

  claim(userId, gatewayId, options) {
    const uid = text(userId, 160);
    const gid = text(gatewayId, 120);
    if (!uid || !gid) throw new Error('user and gateway ids are required');
    const node = this.nodes.get(gid);
    if (!node) throw new Error('gateway node is not registered');
    const now = this.now();
    const existing = this.claims.get(uid);
    if (existing && existing.expiresAt > now
        && existing.gatewayId !== gid
        && (!options || options.force !== true)) {
      return {
        ok: false,
        reason: 'already-claimed',
        claim: Object.assign({}, existing)
      };
    }
    const epoch = Math.max(
      Number(this.epochs.get(uid) || 0),
      existing ? Number(existing.epoch) || 0 : 0
    ) + 1;
    this.epochs.set(uid, epoch);
    const claim = {
      userId: uid,
      gatewayId: gid,
      epoch,
      claimedAt: now,
      renewedAt: now,
      expiresAt: now + Math.max(1000, number(options && options.leaseMs, this.defaultLeaseMs))
    };
    this.claims.set(uid, claim);
    this.claimed += 1;
    return { ok: true, claim: Object.assign({}, claim) };
  }

  lookup(userId) {
    const claim = this.claims.get(text(userId, 160));
    if (!claim) return null;
    if (claim.expiresAt <= this.now()) {
      this.claims.delete(claim.userId);
      this.expired += 1;
      return null;
    }
    return Object.assign({}, claim);
  }

  renew(userId, gatewayId, leaseMs) {
    const claim = this.claims.get(text(userId, 160));
    if (!claim || claim.gatewayId !== text(gatewayId, 120)) return null;
    if (claim.expiresAt <= this.now()) {
      this.claims.delete(claim.userId);
      this.expired += 1;
      return null;
    }
    claim.renewedAt = this.now();
    claim.expiresAt = claim.renewedAt + Math.max(1000, number(leaseMs, this.defaultLeaseMs));
    return Object.assign({}, claim);
  }

  release(userId, gatewayId, epoch) {
    const claim = this.claims.get(text(userId, 160));
    if (!claim) return false;
    if (claim.gatewayId !== text(gatewayId, 120)) return false;
    if (epoch !== undefined && Number(claim.epoch) !== Number(epoch)) return false;
    this.claims.delete(claim.userId);
    this.released += 1;
    return true;
  }

  reapExpired() {
    const now = this.now();
    let count = 0;
    for (const [userId, claim] of this.claims) {
      if (claim.expiresAt <= now) {
        this.claims.delete(userId);
        count += 1;
      }
    }
    this.expired += count;
    return count;
  }

  snapshot() {
    const nodes = Array.from(this.nodes.values()).map((node) => {
      const live = node.active && !node.draining
        && this.now() - node.lastHeartbeat <= this.nodeTimeoutMs;
      return Object.assign({}, node, {
        live,
        loadRatio: Math.round((node.connections / Math.max(1, node.capacity)) * 10000) / 10000
      });
    });
    return {
      nodeTimeoutMs: this.nodeTimeoutMs,
      defaultLeaseMs: this.defaultLeaseMs,
      nodes,
      liveNodes: nodes.filter((node) => node.live).length,
      claims: this.claims.size,
      registered: this.registered,
      claimed: this.claimed,
      released: this.released,
      expired: this.expired
    };
  }
}

module.exports = { GatewayDirectory, hash32 };
