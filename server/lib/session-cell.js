'use strict';

class SessionCell {
  constructor(options) {
    const opts = options || {};
    this.maxConnections = Math.max(1, Number(opts.maxConnections) || 100_000);
    this.connections = new Map();
    this.users = new Map();
    this.draining = false;
    this.opened = 0;
    this.closed = 0;
  }

  get size() {
    return this.connections.size;
  }

  open(connectionId, client) {
    const id = String(connectionId || '');
    if (!id) throw new Error('connectionId is required');
    if (this.connections.has(id)) return { ok: false, reason: 'already-open' };
    if (this.connections.size >= this.maxConnections) {
      return { ok: false, reason: 'capacity' };
    }
    const row = Object.assign({}, client || {}, {
      connectionId: id,
      userId: '',
      openedAt: Date.now()
    });
    this.connections.set(id, row);
    this.opened += 1;
    return { ok: true, session: row };
  }

  bindUser(connectionId, userId) {
    const id = String(connectionId || '');
    const uid = String(userId || '');
    const row = this.connections.get(id);
    if (!row || !uid) return false;
    if (row.userId && row.userId !== uid) this.unbindUser(row);
    row.userId = uid;
    if (!this.users.has(uid)) this.users.set(uid, new Set());
    this.users.get(uid).add(id);
    return true;
  }

  unbindUser(row) {
    if (!row || !row.userId) return;
    const set = this.users.get(row.userId);
    if (!set) return;
    set.delete(row.connectionId);
    if (!set.size) this.users.delete(row.userId);
  }

  close(connectionId) {
    const id = String(connectionId || '');
    const row = this.connections.get(id);
    if (!row) return false;
    this.unbindUser(row);
    this.connections.delete(id);
    this.closed += 1;
    return true;
  }

  get(connectionId) {
    return this.connections.get(String(connectionId || '')) || null;
  }

  forUser(userId) {
    const ids = this.users.get(String(userId || ''));
    if (!ids) return [];
    return Array.from(ids)
      .map((id) => this.connections.get(id))
      .filter(Boolean);
  }

  all() {
    return Array.from(this.connections.values());
  }

  drain() {
    this.draining = true;
  }

  resume() {
    this.draining = false;
  }

  snapshot() {
    return {
      draining: this.draining,
      connections: this.connections.size,
      users: this.users.size,
      maxConnections: this.maxConnections,
      opened: this.opened,
      closed: this.closed,
      loadRatio: this.connections.size / this.maxConnections
    };
  }
}

module.exports = { SessionCell };
