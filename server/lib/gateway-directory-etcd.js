'use strict';

function encodePath(value) {
  return String(value || '').split('/').filter(Boolean)
    .map((part) => encodeURIComponent(part)).join('/');
}

function parseJson(value) {
  try {
    const row = JSON.parse(String(value || ''));
    return row && typeof row === 'object' ? row : null;
  } catch (_) {
    return null;
  }
}

class EtcdGatewayDirectory {
  constructor(options) {
    const opts = options || {};
    this.baseUrl = String(opts.baseUrl || 'http://127.0.0.1:2379').replace(/\/+$/, '');
    this.prefix = '/' + encodePath(opts.prefix || '/xingyan/gateways');
    this.nodeTtlSeconds = Math.max(5, Number(opts.nodeTtlSeconds) || 30);
    this.claimTtlSeconds = Math.max(5, Number(opts.claimTtlSeconds) || 90);
    this.fetchImpl = opts.fetchImpl || fetch;
    this.requestImpl = opts.requestImpl || null;
  }

  key(path) {
    return this.prefix + '/' + encodePath(path);
  }

  nodeKey(id) {
    return this.key('nodes/' + id);
  }

  claimKey(userId) {
    return this.key('claims/' + userId);
  }

  epochKey(userId) {
    return this.key('epochs/' + userId);
  }

  async request(method, path, query, body) {
    const url = new URL(this.baseUrl + path);
    if (query) {
      Object.keys(query).forEach((key) => {
        if (query[key] != null) url.searchParams.set(key, String(query[key]));
      });
    }
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
    let parsed = null;
    try { parsed = text ? JSON.parse(text) : null; } catch (_) { parsed = null; }
    return { status: response.status, body: parsed };
  }

  async getRaw(path) {
    const result = await this.request('GET', path);
    if (result.status === 404) return null;
    if (result.status !== 200 || !result.body || !result.body.node) {
      throw new Error('etcd gateway directory read failed: ' + result.status);
    }
    return {
      raw: String(result.body.node.value || ''),
      ttl: Math.max(0, Number(result.body.node.ttl) || 0),
      modifiedIndex: Number(result.body.node.modifiedIndex) || 0
    };
  }

  async put(path, value, query) {
    return this.request('PUT', path, query, 'value=' + encodeURIComponent(JSON.stringify(value)));
  }

  async delete(path, query) {
    return this.request('DELETE', path, query);
  }

  async register(node) {
    const id = String(node && node.id || '').trim();
    if (!id) throw new Error('gateway node id is required');
    const value = Object.assign({}, node, {
      id,
      registeredAt: Number(node.registeredAt) || Date.now()
    });
    const result = await this.put(this.nodeKey(id), value, {
      ttl: this.nodeTtlSeconds
    });
    if (result.status !== 200 && result.status !== 201) {
      throw new Error('etcd gateway node register failed: ' + result.status);
    }
    return value;
  }

  async heartbeat(id, input) {
    const row = Object.assign({}, input || {}, { id: String(id || '') });
    return this.register(row);
  }

  async unregister(id) {
    const result = await this.delete(this.nodeKey(id));
    return result.status === 200 || result.status === 404;
  }

  async listNodes() {
    const result = await this.request('GET', this.prefix + '/nodes', { recursive: 'true' });
    if (result.status === 404) return [];
    if (result.status !== 200 || !result.body || !result.body.node) return [];
    const rows = result.body.node.nodes || [];
    return rows.map((row) => parseJson(row.value)).filter(Boolean);
  }

  async bumpEpoch(userId) {
    const path = this.epochKey(userId);
    for (let attempt = 0; attempt < 6; attempt += 1) {
      const current = await this.getRaw(path);
      const previous = current ? Number(parseJson(current.raw) && parseJson(current.raw).value) || 0 : 0;
      const next = previous + 1;
      const result = await this.put(path, { value: next }, current
        ? { prevValue: current.raw }
        : { prevExist: 'false' });
      if (result.status === 200 || result.status === 201) return next;
      if (result.status !== 409 && result.status !== 412) {
        throw new Error('etcd gateway epoch write failed: ' + result.status);
      }
    }
    throw new Error('etcd gateway epoch contention for ' + userId);
  }

  async claim(userId, gatewayId, options) {
    const uid = String(userId || '');
    const gid = String(gatewayId || '');
    if (!uid || !gid) throw new Error('user and gateway ids are required');
    const existingRaw = await this.getRaw(this.claimKey(uid));
    const existing = existingRaw ? parseJson(existingRaw.raw) : null;
    if (existing && existing.gatewayId !== gid
        && !(options && options.force === true)) {
      return {
        ok: false,
        reason: 'already-claimed',
        claim: existing
      };
    }
    const epoch = await this.bumpEpoch(uid);
    const claim = {
      userId: uid,
      gatewayId: gid,
      epoch,
      claimedAt: Date.now(),
      expiresAt: Date.now() + this.claimTtlSeconds * 1000
    };
    const result = await this.put(this.claimKey(uid), claim, existingRaw
      ? { prevValue: existingRaw.raw, ttl: this.claimTtlSeconds }
      : { prevExist: 'false', ttl: this.claimTtlSeconds });
    if (result.status !== 200 && result.status !== 201) {
      return { ok: false, reason: 'claim-race' };
    }
    return { ok: true, claim };
  }

  async lookup(userId) {
    const raw = await this.getRaw(this.claimKey(userId));
    if (!raw) return null;
    if (raw.ttl <= 0) return null;
    return parseJson(raw.raw);
  }

  async renew(userId, gatewayId, leaseSeconds) {
    const row = await this.getRaw(this.claimKey(userId));
    const claim = row && parseJson(row.raw);
    if (!claim || claim.gatewayId !== String(gatewayId || '')) return null;
    const next = Object.assign({}, claim, {
      renewedAt: Date.now(),
      expiresAt: Date.now() + Math.max(5, Number(leaseSeconds) || this.claimTtlSeconds) * 1000
    });
    const result = await this.put(this.claimKey(userId), next, {
      prevValue: row.raw,
      ttl: Math.max(5, Number(leaseSeconds) || this.claimTtlSeconds)
    });
    return result.status === 200 ? next : null;
  }

  async release(userId, gatewayId, epoch) {
    const row = await this.getRaw(this.claimKey(userId));
    if (!row) return false;
    const claim = parseJson(row.raw);
    if (!claim || claim.gatewayId !== String(gatewayId || '')) return false;
    if (epoch !== undefined && Number(claim.epoch) !== Number(epoch)) return false;
    const result = await this.delete(this.claimKey(userId), { prevValue: row.raw });
    return result.status === 200 || result.status === 404;
  }

  async snapshot() {
    const nodes = await this.listNodes();
    return {
      backend: 'etcd',
      prefix: this.prefix,
      nodes,
      liveNodes: nodes.length
    };
  }
}

module.exports = { EtcdGatewayDirectory };
