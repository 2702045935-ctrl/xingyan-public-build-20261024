'use strict';

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const found = process.argv.find((value) => value.startsWith(prefix));
  return found ? found.slice(prefix.length) : fallback;
}

function listArg(name) {
  return String(arg(name, '')).split(',').map((value) => value.trim()).filter(Boolean);
}

async function getJson(url, headers) {
  const response = await fetch(url, {
    headers: headers || {},
    signal: AbortSignal.timeout(2500)
  });
  const text = await response.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch (_) { data = null; }
  return { ok: response.ok, status: response.status, data };
}

async function main() {
  const blockers = [];
  const warnings = [];
  const backend = String(arg('backend', process.env.GATEWAY_BACKEND_HTTP || '')).replace(/\/+$/, '');
  const secret = String(arg('secret', process.env.GATEWAY_ADMIN_SECRET || ''));
  const directoryBackend = String(arg('directory-backend',
    process.env.GATEWAY_DIRECTORY_BACKEND || 'local')).toLowerCase();
  const fanoutMode = String(arg('fanout-mode',
    process.env.GATEWAY_FANOUT_MODE || 'off')).toLowerCase();
  const canaryPercent = Number(arg('canary-percent',
    process.env.GATEWAY_FANOUT_CANARY_PERCENT || '0'));
  const gateways = listArg('gateways');
  if (!backend) blockers.push('missing-backend-url');
  if (!secret || secret === 'change-me-in-secret-store') blockers.push('missing-gateway-secret');
  if (!['local', 'etcd'].includes(directoryBackend)) blockers.push('invalid-directory-backend');
  if (!['off', 'shadow', 'canary', 'live'].includes(fanoutMode)) blockers.push('invalid-fanout-mode');
  if (canaryPercent < 0 || canaryPercent > 100) blockers.push('invalid-canary-percent');
  if (fanoutMode === 'canary' && canaryPercent <= 0) blockers.push('canary-percent-required');
  if (fanoutMode === 'live' && canaryPercent !== 100) {
    warnings.push('live mode is enabled without 100 percent canary transition');
  }
  if (!gateways.length) warnings.push('no-gateway-endpoints-supplied');

  let health = null;
  let directory = null;
  if (backend) {
    try {
      health = await getJson(backend + '/api/health');
      if (!health.ok || !health.data || health.data.ok !== true) {
        blockers.push('backend-health-failed');
      }
      const response = await getJson(backend + '/__gateway/directory', {
        'x-gateway-admin-secret': secret
      });
      if (!response.ok) blockers.push('directory-auth-or-read-failed');
      else directory = response.data && response.data.data && response.data.data.directory;
      if (!directory || Number(directory.liveNodes) < 2) {
        blockers.push('less-than-two-live-gateway-nodes');
      }
      if (directory && directory.mode !== directoryBackend) {
        warnings.push(`backend-directory-mode=${directory.mode || 'unknown'} requested=${directoryBackend}`);
      }
    } catch (error) {
      blockers.push('backend-unreachable:' + String(error && error.message || error));
    }
  }

  const gatewayHealth = [];
  for (const endpoint of gateways) {
    try {
      const result = await getJson(String(endpoint).replace(/\/+$/, '') + '/health');
      const row = {
        endpoint,
        ok: result.ok && result.data && result.data.ok === true,
        upstreamReady: !!(result.data && result.data.upstreamReady),
        clients: result.data && Number(result.data.clients) || 0
      };
      gatewayHealth.push(row);
      if (!row.ok) blockers.push('gateway-health-failed:' + endpoint);
      if (!row.upstreamReady) blockers.push('gateway-upstream-not-ready:' + endpoint);
    } catch (error) {
      gatewayHealth.push({ endpoint, ok: false, error: String(error && error.message || error) });
      blockers.push('gateway-unreachable:' + endpoint);
    }
  }

  const report = {
    ok: blockers.length === 0,
    checkedAt: new Date().toISOString(),
    config: {
      backend,
      directoryBackend,
      fanoutMode,
      canaryPercent,
      gateways
    },
    backendHealth: health && health.data,
    directory,
    gatewayHealth,
    blockers,
    warnings
  };
  const output = arg('out', '');
  if (output) {
    const fs = require('fs');
    const path = require('path');
    fs.writeFileSync(path.resolve(output), JSON.stringify(report, null, 2) + '\n', 'utf8');
  }
  console.log(JSON.stringify(report));
  if (!report.ok) process.exitCode = 1;
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
