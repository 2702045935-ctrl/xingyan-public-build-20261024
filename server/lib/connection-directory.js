'use strict';

const crypto = require('crypto');

function connectionId(record) {
  const supplied = String(record && record.connectionId || '').trim();
  if (supplied) return supplied;
  return 'conn_' + crypto.randomBytes(16).toString('hex');
}

class LocalConnectionDirectory {
  constructor(options) {
    const opts = options || {};
    this.ttlMs = Math.max(1000, Number(opts.ttlMs) || 45000);
    this.maxConnections = Math.max(1, Number(opts.maxConnections) || 1_000_000);
    this.now = typeof opts.now === 'function' ? opts.now : Date.now;
    this.records = new Map();
    this.byUser = new Map();
    this.byGateway = new Map();
    this.epoch = 0;
  }

  register(record) {
    const opts = record || {};
    const userId = String(opts.userId || '').trim();
    const gatewayId = String(opts.gatewayId || '').trim();
    if (!userId) throw new Error('connection userId is required');
    if (!gatewayId) throw new Error('connection gatewayId is required');
    this.sweepExpired();
    if (!this.records.has(String(opts.connectionId || ''))
        && this.records.size >= this.maxConnections) {
      throw new Error('connection directory capacity exceeded');
    }
    const id = connectionId(opts);
    const existing = this.records.get(id);
    if (existing) this.unlink(existing);
    const now = this.now();
    const next = {
      connectionId: id,
      userId,
      gatewayId,
      region: String(opts.region || ''),
      shard: Number.isSafeInteger(Number(opts.shard)) ? Number(opts.shard) : -1,
      deviceId: String(opts.deviceId || ''),
      connectedAt: Number(opts.connectedAt) || now,
      expiresAt: now + this.ttlMs,
      epoch: ++this.epoch
    };
    this.records.set(id, next);
    if (!this.byUser.has(userId)) this.byUser.set(userId, new Set());
    this.byUser.get(userId).add(id);
    if (!this.byGateway.has(gatewayId)) this.byGateway.set(gatewayId, new Set());
    this.byGateway.get(gatewayId).add(id);
    return Object.assign({}, next);
  }

  heartbeat(id) {
    const current = this.records.get(String(id || ''));
    if (!current || current.expiresAt <= this.now()) {
      if (current) this.unlink(current);
      return null;
    }
    current.expiresAt = this.now() + this.ttlMs;
    current.epoch = ++this.epoch;
    return Object.assign({}, current);
  }

  unregister(id) {
    const current = this.records.get(String(id || ''));
    if (!current) return false;
    this.unlink(current);
    return true;
  }

  get(id) {
    const current = this.records.get(String(id || ''));
    if (!current) return null;
    if (current.expiresAt <= this.now()) {
      this.unlink(current);
      return null;
    }
    return Object.assign({}, current);
  }

  byUserId(userId) {
    const ids = this.byUser.get(String(userId || ''));
    if (!ids) return [];
    const rows = [];
    for (const id of Array.from(ids)) {
      const record = this.get(id);
      if (record) rows.push(record);
    }
    return rows;
  }

  gatewaysForUser(userId) {
    return Array.from(new Set(this.byUserId(userId).map((row) => row.gatewayId)));
  }

  gatewayConnections(gatewayId) {
    const ids = this.byGateway.get(String(gatewayId || ''));
    if (!ids) return [];
    const rows = [];
    for (const id of Array.from(ids)) {
      const record = this.get(id);
      if (record) rows.push(record);
    }
    return rows;
  }

  sweepExpired() {
    const now = this.now();
    let removed = 0;
    for (const record of Array.from(this.records.values())) {
      if (record.expiresAt <= now) {
        this.unlink(record);
        removed += 1;
      }
    }
    return removed;
  }

  stats() {
    return {
      connections: this.records.size,
      users: this.byUser.size,
      gateways: this.byGateway.size,
      ttlMs: this.ttlMs
    };
  }

  unlink(record) {
    this.records.delete(record.connectionId);
    const user = this.byUser.get(record.userId);
    if (user) {
      user.delete(record.connectionId);
      if (!user.size) this.byUser.delete(record.userId);
    }
    const gateway = this.byGateway.get(record.gatewayId);
    if (gateway) {
      gateway.delete(record.connectionId);
      if (!gateway.size) this.byGateway.delete(record.gatewayId);
    }
  }
}

module.exports = { LocalConnectionDirectory };
