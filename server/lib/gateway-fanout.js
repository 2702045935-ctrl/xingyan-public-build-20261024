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
    const dryRun = row.dryRun === true;
    const nodes = Array.isArray(row.nodes) ? row.nodes : [];
    const results = [];
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
              body: JSON.stringify({ publishId, userIds, payload, dryRun }),
              signal: AbortSignal.timeout(this.timeoutMs)
            }
          );
          const body = await response.json().catch(() => ({}));
          if (!response.ok || body.ok !== true) {
            lastError = String(body.error || response.status);
            continue;
          }
          ok = true;
          const delivered = Number(body.delivered) || 0;
          const wouldDeliver = Number(body.wouldDeliver) || delivered;
          results.push({
            nodeId: node.id || '',
            ok: true,
            delivered: dryRun ? 0 : delivered,
            wouldDeliver
          });
        } catch (error) {
          lastError = String(error && error.message || error);
        }
      }
      if (!ok) results.push({ nodeId: node.id || '', ok: false, error: lastError });
    }
    return {
      publishId,
      dryRun,
      ok: results.every((result) => result.ok),
      delivered: results.reduce((sum, result) => sum + (Number(result.delivered) || 0), 0),
      wouldDeliver: results.reduce((sum, result) => sum + (Number(result.wouldDeliver) || 0), 0),
      results
    };
  }
}

module.exports = { GatewayFanoutBus };
