'use strict';

function encodePath(value) {
  return String(value || '').split('/').filter(Boolean)
    .map((part) => encodeURIComponent(part)).join('/');
}

function parse(value) {
  try {
    const row = JSON.parse(String(value || ''));
    return row && typeof row === 'object' ? row : null;
  } catch (_) {
    return null;
  }
}

class EtcdSessionOwnership {
  constructor(options) {
    const opts = options || {};
    this.baseUrl = String(opts.baseUrl || 'http://127.0.0.1:2379').replace(/\/+$/, '');
    this.prefix = '/' + encodePath(opts.prefix || '/xingyan/gateway-sessions');
    this.leaseSeconds = Math.max(5, Number(opts.leaseSeconds) || 90);
    this.fetchImpl = opts.fetchImpl || fetch;
    this.requestImpl = opts.requestImpl || null;
  }

  key(userId, connectionId) {
    return this.prefix + '/' + encodePath(userId) + '/' + encodePath(connectionId);
  }

  epochKey(userId) {
    return this.prefix + '/epochs/' + encodePath(userId);
  }

  async request(method, path, query, body) {
    const url = new URL(this.baseUrl + path);
    Object.keys(query || {}).forEach((key) => {
      if (query[key] != null) url.searchParams.set(key, String(query[key]));
    });
    if (this.requestImpl) return this.requestImpl(method, url.toString(), body || '');
    const response = await this.fetchImpl(url.toString(), {
      method,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        Accept: 'application/json'
      },
      body: body || undefined,
      signal: AbortSignal.timeout(2500)
    });
    const text = await response.text();
    let data = null;
    try { data = text ? JSON.parse(text) : null; } catch (_) { data = null; }
    return { status: response.status, body: data };
  }

  async getRaw(path) {
    const result = await this.request('GET', path);
    if (result.status === 404) return null;
    if (result.status !== 200 || !result.body || !result.body.node) {
      throw new Error('etcd session read failed: ' + result.status);
    }
    return {
      raw: String(result.body.node.value || ''),
      ttl: Math.max(0, Number(result.body.node.ttl) || 0)
    };
  }

  async put(path, value, query) {
    return this.request('PUT', path, query,
      'value=' + encodeURIComponent(JSON.stringify(value)));
  }

  async bumpEpoch(userId) {
    const path = this.epochKey(userId);
    for (let attempt = 0; attempt < 6; attempt += 1) {
      const current = await this.getRaw(path);
      const currentValue = current && parse(current.raw)
        ? Number(parse(current.raw).value) || 0
        : 0;
      const next = currentValue + 1;
      const result = await this.put(path, { value: next }, current
        ? { prevValue: current.raw }
        : { prevExist: 'false' });
      if (result.status === 200 || result.status === 201) return next;
      if (result.status !== 409 && result.status !== 412) {
        throw new Error('etcd session epoch failed: ' + result.status);
      }
    }
    throw new Error('etcd session epoch contention');
  }

  async claim(userId, connectionId, gatewayId, options) {
    const uid = String(userId || '');
    const cid = String(connectionId || '');
    const gid = String(gatewayId || '');
    if (!uid || !cid || !gid) throw new Error('session ids are required');
    const path = this.key(uid, cid);
    const existingRaw = await this.getRaw(path);
    const existing = existingRaw && parse(existingRaw.raw);
    if (existing && existing.gatewayId !== gid
        && !(options && options.force === true)) {
      return { ok: false, reason: 'connection-owned', claim: existing };
    }
    const epoch = await this.bumpEpoch(uid);
    const ttl = Math.max(5, Number(options && options.leaseSeconds) || this.leaseSeconds);
    const claim = {
      userId: uid,
      connectionId: cid,
      gatewayId: gid,
      epoch,
      claimedAt: Date.now(),
      expiresAt: Date.now() + ttl * 1000
    };
    const result = await this.put(path, claim, existingRaw
      ? { prevValue: existingRaw.raw, ttl }
      : { prevExist: 'false', ttl });
    if (result.status !== 200 && result.status !== 201) {
      return { ok: false, reason: 'claim-race' };
    }
    return { ok: true, claim };
  }

  async lookup(userId, connectionId) {
    const raw = await this.getRaw(this.key(userId, connectionId));
    return raw && raw.ttl > 0 ? parse(raw.raw) : null;
  }

  async renew(userId, connectionId, gatewayId, leaseSeconds) {
    const path = this.key(userId, connectionId);
    const raw = await this.getRaw(path);
    const claim = raw && parse(raw.raw);
    if (!claim || claim.gatewayId !== String(gatewayId || '')) return null;
    const ttl = Math.max(5, Number(leaseSeconds) || this.leaseSeconds);
    const next = Object.assign({}, claim, {
      renewedAt: Date.now(),
      expiresAt: Date.now() + ttl * 1000
    });
    const result = await this.put(path, next, { prevValue: raw.raw, ttl });
    return result.status === 200 ? next : null;
  }

  async release(userId, connectionId, gatewayId, epoch) {
    const path = this.key(userId, connectionId);
    const raw = await this.getRaw(path);
    const claim = raw && parse(raw.raw);
    if (!claim || claim.gatewayId !== String(gatewayId || '')) return false;
    if (epoch !== undefined && Number(claim.epoch) !== Number(epoch)) return false;
    const result = await this.request('DELETE', path, { prevValue: raw.raw });
    return result.status === 200 || result.status === 404;
  }
}

module.exports = { EtcdSessionOwnership };
