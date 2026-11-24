'use strict';

class GatewayFanoutBus {
  constructor(options) {
    const opts = options || {};
    this.fetchImpl = opts.fetchImpl || fetch;
    this.secret = String(opts.secret || '');
    this.timeoutMs = Math.max(100, Number(opts.timeoutMs) || 2500);
    this.retries = Math.max(0, Number(opts.retries) || 2);
  }

  async publish(input) {
    const row = input || {};
    const payload = row.payload || {};
    const publishId = String(row.publishId || '');
    const nodes = Array.isArray(row.nodes) ? row.nodes : [];
    const results = [];
    let delivered = 0;
    for (const node of nodes) {
      const userIds = (node.userIds || []).map((value) => String(value));
      if (!userIds.length || !node.endpoint) continue;
      let lastError = '';
      let ok = false;
      for (let attempt = 0; attempt <= this.retries && !ok; attempt += 1) {
        try {
          const response = await this.fetchImpl(
            String(node.endpoint).replace(/\/+$/, '') + '/__gateway/publish',
            {
              method: 'POST',
              headers: {
                'content-type': 'application/json',
                'x-gateway-admin-secret': this.secret
              },
              body: JSON.stringify({ publishId, userIds, payload }),
              signal: AbortSignal.timeout(this.timeoutMs)
            }
          );
          const body = await response.json().catch(() => ({}));
          if (!response.ok || body.ok !== true) {
            lastError = String(body.error || response.status);
            continue;
          }
          ok = true;
          delivered += Number(body.delivered) || 0;
          results.push({ nodeId: node.id || '', ok: true, delivered: Number(body.delivered) || 0 });
        } catch (error) {
          lastError = String(error && error.message || error);
        }
      }
      if (!ok) results.push({ nodeId: node.id || '', ok: false, error: lastError });
    }
    return {
      publishId,
      ok: results.every((result) => result.ok),
      delivered,
      results
    };
  }
}

module.exports = { GatewayFanoutBus };
