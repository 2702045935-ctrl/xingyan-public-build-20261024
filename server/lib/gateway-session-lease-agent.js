'use strict';

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

/**
 * Keeps local and globally-backed connection leases alive while a client
 * remains attached to a gateway. Renewal is fail-closed: once ownership is
 * lost, or the remote lease has been unavailable beyond its safety window,
 * the client is disconnected so it can fall back to the legacy realtime path.
 */
class GatewaySessionLeaseAgent {
  constructor(options) {
    const opts = options || {};
    if (!opts.sessions || typeof opts.sessions.all !== 'function') {
      throw new Error('sessions is required');
    }
    if (!opts.ownership || typeof opts.ownership.renew !== 'function') {
      throw new Error('ownership is required');
    }
    this.sessions = opts.sessions;
    this.ownership = opts.ownership;
    this.gatewayId = String(opts.gatewayId || '');
    if (!this.gatewayId) throw new Error('gatewayId is required');
    this.leaseMs = Math.max(5000, Number(opts.leaseMs) || 90_000);
    this.renewalMs = clamp(
      Number(opts.renewalMs) || Math.floor(this.leaseMs / 3),
      1000,
      Math.max(1000, Math.floor(this.leaseMs / 2))
    );
    this.remoteFailureGraceMs = clamp(
      Number(opts.remoteFailureGraceMs) || Math.floor(this.leaseMs * 0.67),
      this.renewalMs,
      this.leaseMs
    );
    this.remoteBatchSize = clamp(Number(opts.remoteBatchSize) || 500, 1, 2000);
    this.remoteRenew = typeof opts.remoteRenew === 'function' ? opts.remoteRenew : null;
    this.closeClient = typeof opts.closeClient === 'function'
      ? opts.closeClient
      : (client) => {
        if (client && client.socket && typeof client.socket.destroy === 'function') {
          client.socket.destroy();
        }
      };
    this.now = typeof opts.now === 'function' ? opts.now : Date.now;
    this.timer = null;
    this.inFlight = null;
    this.stats = {
      renewed: 0,
      remoteRenewed: 0,
      localLost: 0,
      remoteLost: 0,
      remoteFailures: 0,
      lastRenewAt: 0,
      lastError: '',
      leaseMs: this.leaseMs,
      renewalMs: this.renewalMs
    };
  }

  start() {
    if (this.timer) return false;
    this.timer = setInterval(() => {
      this.renewOnce().catch((error) => {
        this.stats.remoteFailures += 1;
        this.stats.lastError = String(error && error.message || error);
      });
    }, this.renewalMs);
    if (this.timer.unref) this.timer.unref();
    return true;
  }

  stop() {
    if (!this.timer) return false;
    clearInterval(this.timer);
    this.timer = null;
    return true;
  }

  snapshot() {
    return Object.assign({}, this.stats);
  }

  failClient(client, reason) {
    if (!client || client.__leaseFailed) return false;
    client.__leaseFailed = true;
    try {
      this.closeClient(client, reason);
    } catch (_) { /* closing is best effort */ }
    return true;
  }

  async renewOnce() {
    if (this.inFlight) return this.inFlight;
    this.inFlight = this.renewCurrentClients().finally(() => {
      this.inFlight = null;
    });
    return this.inFlight;
  }

  async renewCurrentClients() {
    const clients = this.sessions.all().filter((client) =>
      client && client.userId && !client.__leaseFailed
    );
    const renewable = [];
    for (const client of clients) {
      const claim = this.ownership.renew(
        client.userId,
        client.connectionId,
        this.gatewayId,
        this.leaseMs
      );
      if (!claim) {
        this.stats.localLost += 1;
        this.failClient(client, 'local-session-lease-lost');
        continue;
      }
      client.localLeaseExpiresAt = claim.expiresAt;
      this.stats.renewed += 1;
      renewable.push(client);
    }

    if (this.remoteRenew && renewable.length) {
      const remoteRenewable = renewable.filter((client) => client.remoteLeaseReady !== false);
      for (let offset = 0; offset < remoteRenewable.length; offset += this.remoteBatchSize) {
        const batch = remoteRenewable.slice(offset, offset + this.remoteBatchSize);
        await this.renewRemoteBatch(batch);
      }
    }
    this.stats.lastRenewAt = this.now();
    return this.snapshot();
  }

  async renewRemoteBatch(batch) {
    let results;
    try {
      results = await this.remoteRenew(batch.map((client) => ({
        userId: client.userId,
        connectionId: client.connectionId
      })));
      if (!Array.isArray(results) || results.length !== batch.length) {
        throw new Error('remote lease renewal returned an invalid batch');
      }
    } catch (error) {
      this.markRemoteFailure(batch, error);
      return;
    }

    const at = this.now();
    for (let index = 0; index < batch.length; index += 1) {
      const client = batch[index];
      const result = results[index];
      if (result && result.ok === true && result.claim) {
        client.remoteFailureSince = 0;
        client.remoteLeaseExpiresAt = Number(result.claim.expiresAt) || 0;
        if (result.claim.epoch !== undefined) client.remoteEpoch = result.claim.epoch;
        this.stats.remoteRenewed += 1;
        continue;
      }
      if (result && result.ok === true) {
        this.stats.remoteLost += 1;
        this.failClient(client, 'remote-session-lease-lost');
        continue;
      }
      this.markRemoteFailure([client], new Error(
        String(result && result.error || 'remote lease renewal failed')
      ), at);
    }
  }

  markRemoteFailure(batch, error, at) {
    const now = at === undefined ? this.now() : at;
    const message = String(error && error.message || error || 'remote lease renewal failed');
    this.stats.remoteFailures += 1;
    this.stats.lastError = message;
    for (const client of batch) {
      if (!client || client.__leaseFailed) continue;
      if (!client.remoteFailureSince) client.remoteFailureSince = now;
      if (now - client.remoteFailureSince >= this.remoteFailureGraceMs) {
        this.stats.remoteLost += 1;
        this.failClient(client, 'remote-session-lease-expired');
      }
    }
  }
}

module.exports = { GatewaySessionLeaseAgent };
