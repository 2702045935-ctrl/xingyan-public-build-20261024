'use strict';

function keyName(shard) {
  const value = Number(shard);
  if (!Number.isInteger(value) || value < 0) throw new Error('shard must be a non-negative integer');
  return 'shard-' + value;
}

function parseLease(value) {
  try {
    const row = JSON.parse(String(value || ''));
    if (!row || !row.ownerId || !Number.isSafeInteger(Number(row.epoch))) return null;
    return row;
  } catch (_) {
    return null;
  }
}

function encodePath(value) {
  return String(value || '').split('/').filter(Boolean)
    .map((part) => encodeURIComponent(part)).join('/');
}

class EtcdLeaseManager {
  constructor(options) {
    const opts = options || {};
    this.baseUrl = String(opts.baseUrl || 'http://127.0.0.1:2379').replace(/\/+$/, '');
    this.prefix = '/' + encodePath(opts.prefix || '/xingyan/dual-cell/leases');
    this.ownerId = String(opts.ownerId || '').trim();
    this.ttlMs = Math.max(1000, Number(opts.ttlMs) || 30000);
    this.fetchImpl = opts.fetchImpl || fetch;
    this.requestImpl = opts.requestImpl || null;
    if (!this.ownerId) throw new Error('etcd lease ownerId is required');
  }

  key(shard) {
    return this.prefix + '/' + keyName(shard);
  }

  epochKey(shard) {
    return this.prefix + '/epochs/' + keyName(shard);
  }

  ttlSeconds() {
    return Math.max(1, Math.ceil(this.ttlMs / 1000));
  }

  async request(method, path, query, body) {
    const url = new URL(this.baseUrl + path);
    if (query) {
      for (const [key, value] of Object.entries(query)) {
        if (value != null) url.searchParams.set(key, String(value));
      }
    }
    if (this.requestImpl) {
      return this.requestImpl(method, url.toString(), body || '');
    }
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

  async read(shard) {
    const result = await this.request('GET', this.key(shard));
    if (result.status === 404) return null;
    if (result.status !== 200 || !result.body || !result.body.node) {
      throw new Error('etcd lease read failed: ' + result.status);
    }
    const node = result.body.node;
    const value = parseLease(node.value);
    if (!value) throw new Error('etcd lease value is invalid for shard ' + Number(shard));
    return {
      raw: String(node.value || ''),
      ownerId: String(value.ownerId),
      epoch: Number(value.epoch),
      ttlSeconds: Math.max(0, Number(node.ttl) || 0),
      modifiedIndex: Number(node.modifiedIndex) || 0
    };
  }

  async readEpoch(shard) {
    const result = await this.request('GET', this.epochKey(shard));
    if (result.status === 404) return 0;
    if (result.status !== 200 || !result.body || !result.body.node) {
      throw new Error('etcd epoch read failed: ' + result.status);
    }
    const value = Number(result.body.node.value);
    if (!Number.isSafeInteger(value) || value < 0) {
      throw new Error('etcd epoch value is invalid for shard ' + Number(shard));
    }
    return value;
  }

  async bumpEpoch(shard) {
    for (let attempt = 0; attempt < 6; attempt += 1) {
      const current = await this.readEpoch(shard);
      const next = current + 1;
      const result = await this.request('PUT', this.epochKey(shard), current > 0
        ? { prevValue: String(current) }
        : { prevExist: 'false' }, 'value=' + encodeURIComponent(String(next)));
      if (result.status === 200 || result.status === 201) return next;
      if (result.status !== 409 && result.status !== 412) {
        throw new Error('etcd epoch bump failed: ' + result.status);
      }
    }
    throw new Error('etcd epoch contention for shard ' + Number(shard));
  }

  async validate(shard) {
    const lease = await this.read(shard);
    if (!lease) return { ok: false, reason: 'not-owner', lease: null };
    if (lease.ownerId !== this.ownerId) return { ok: false, reason: 'not-owner', lease };
    if (lease.ttlSeconds <= 0) return { ok: false, reason: 'expired', lease };
    return { ok: true, lease };
  }

  async acquire(shard) {
    const key = this.key(shard);
    const ttl = this.ttlSeconds();
    for (let attempt = 0; attempt < 6; attempt += 1) {
      const current = await this.read(shard);
      if (current && current.ownerId === this.ownerId && current.ttlSeconds > 0) {
        return this.renew(shard);
      }
      if (current && current.ownerId !== this.ownerId && current.ttlSeconds > 0) {
        throw new Error('shard lease is held by ' + current.ownerId);
      }
      const epoch = await this.bumpEpoch(shard);
      const value = JSON.stringify({ ownerId: this.ownerId, epoch });
      const result = await this.request('PUT', key, current
        ? { prevValue: current.raw, ttl }
        : { prevExist: 'false', ttl }, 'value=' + encodeURIComponent(value));
      if (result.status === 200 || result.status === 201) {
        return {
          shard: Number(shard),
          ownerId: this.ownerId,
          epoch,
          ttlMs: this.ttlMs
        };
      }
      if (result.status !== 409 && result.status !== 412) {
        throw new Error('etcd lease acquire failed: ' + result.status);
      }
    }
    throw new Error('etcd lease acquire contention for shard ' + Number(shard));
  }

  async renew(shard) {
    const current = await this.read(shard);
    if (!current || current.ownerId !== this.ownerId || current.ttlSeconds <= 0) {
      throw new Error('cannot renew a lost etcd lease for shard ' + Number(shard));
    }
    const result = await this.request('PUT', this.key(shard), {
      prevValue: current.raw,
      ttl: this.ttlSeconds()
    }, 'value=' + encodeURIComponent(current.raw));
    if (result.status !== 200) {
      throw new Error('etcd lease renew failed: ' + result.status);
    }
    return {
      shard: Number(shard),
      ownerId: this.ownerId,
      epoch: current.epoch,
      ttlMs: this.ttlMs
    };
  }

  async release(shard) {
    const current = await this.read(shard);
    if (!current) return true;
    if (current.ownerId !== this.ownerId) return false;
    const result = await this.request('DELETE', this.key(shard), {
      prevValue: current.raw
    });
    if (result.status !== 200 && result.status !== 404) {
      throw new Error('etcd lease release failed: ' + result.status);
    }
    return true;
  }
}

module.exports = {
  EtcdLeaseManager,
  parseLease
};
