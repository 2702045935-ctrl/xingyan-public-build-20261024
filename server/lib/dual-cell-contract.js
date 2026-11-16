'use strict';

const crypto = require('crypto');

function stable(value) {
  if (value === null || typeof value !== 'object') {
    return JSON.stringify(value === undefined ? null : value);
  }
  if (Array.isArray(value)) return '[' + value.map(stable).join(',') + ']';
  return '{' + Object.keys(value).sort().map((key) =>
    JSON.stringify(key) + ':' + stable(value[key])
  ).join(',') + '}';
}

function hash(value) {
  return crypto.createHash('sha256').update(stable(value)).digest('hex');
}

function text(value, max) {
  return String(value == null ? '' : value).trim().slice(0, max || 500);
}

function normalizeRoot(value) {
  return String(value || '').replace(/\\/g, '/').replace(/\/+$/, '');
}

function pathContains(parent, child) {
  return child === parent || child.startsWith(parent + '/');
}

function baseUrlOf(value) {
  try {
    const url = new URL(String(value || ''));
    if (url.username || url.password) return null;
    return url;
  } catch (_) {
    return null;
  }
}

function validateDualCellPlan(plan) {
  const input = plan || {};
  const failures = [];
  const fail = (code, details) => failures.push(Object.assign({ code }, details || {}));
  if (Number(input.version) !== 1) {
    fail('version', { expected: 1, actual: input.version });
  }
  if (text(input.mode, 20) !== 'shadow') {
    fail('mode', { expected: 'shadow', actual: input.mode });
  }
  if (text(input.writeMode, 20) !== 'disabled') {
    fail('write-mode', { expected: 'disabled', actual: input.writeMode });
  }
  if (!/^[a-f0-9]{64}$/i.test(text(input.routePlanHash, 64))) {
    fail('route-plan-hash');
  }

  const cells = input.cells || {};
  const a = cells.a || {};
  const b = cells.b || {};
  const aId = text(a.id, 80);
  const bId = text(b.id, 80);
  const aHost = text(a.host, 200).toLowerCase();
  const bHost = text(b.host, 200).toLowerCase();
  const aRoot = normalizeRoot(text(a.dataRoot, 500));
  const bRoot = normalizeRoot(text(b.dataRoot, 500));
  const aDomain = text(a.failureDomain, 120);
  const bDomain = text(b.failureDomain, 120);
  const aUrl = baseUrlOf(a.baseUrl);
  const bUrl = baseUrlOf(b.baseUrl);
  if (!aId || !bId) fail('cell-id');
  if (aId && aId === bId) fail('cell-id-duplicate', { id: aId });
  if (!aHost || !bHost) fail('cell-host');
  if (aHost && aHost === bHost) fail('cell-host-shared', { host: aHost });
  if (!aRoot || !bRoot) fail('cell-data-root');
  if (aRoot && bRoot
      && (pathContains(aRoot, bRoot) || pathContains(bRoot, aRoot))) {
    fail('cell-data-root-overlap', { a: aRoot, b: bRoot });
  }
  if (!aDomain || !bDomain) fail('failure-domain');
  if (aDomain && aDomain === bDomain) {
    fail('failure-domain-shared', { failureDomain: aDomain });
  }
  if (text(a.role, 20) !== 'primary') fail('cell-a-role');
  if (text(b.role, 20) !== 'shadow') fail('cell-b-role');
  if (!aUrl || !bUrl) fail('cell-base-url');
  if (aUrl && aUrl.hostname.toLowerCase() !== aHost) {
    fail('cell-a-base-url-host', { host: aHost, urlHost: aUrl.hostname });
  }
  if (bUrl && bUrl.hostname.toLowerCase() !== bHost) {
    fail('cell-b-base-url-host', { host: bHost, urlHost: bUrl.hostname });
  }
  if (aUrl && bUrl && aUrl.origin === bUrl.origin) {
    fail('cell-origin-shared', { origin: aUrl.origin });
  }
  for (const [id, url] of [['a', aUrl], ['b', bUrl]]) {
    const local = url && /^(127\.0\.0\.1|::1|localhost)$/i.test(url.hostname);
    if (url && url.protocol !== 'https:' && !local) {
      fail('cell-' + id + '-insecure-transport', { protocol: url.protocol });
    }
  }

  const traffic = input.traffic || {};
  const sampleRate = Number(traffic.sampleRate);
  const maxRequestsPerSecond = Number(traffic.maxRequestsPerSecond);
  if (!(sampleRate > 0 && sampleRate <= 0.1)) {
    fail('sample-rate', { value: traffic.sampleRate, max: 0.1 });
  }
  if (!Number.isInteger(maxRequestsPerSecond)
      || maxRequestsPerSecond < 1
      || maxRequestsPerSecond > 1000) {
    fail('max-requests-per-second', { value: traffic.maxRequestsPerSecond });
  }
  if (traffic.readOnly !== true) fail('traffic-read-only');
  if (traffic.writeMirror !== false) fail('traffic-write-mirror');

  const compare = input.compare || {};
  const timeoutMs = Number(compare.timeoutMs);
  const requiredSamples = Number(compare.requiredSamples);
  if (!Number.isInteger(timeoutMs) || timeoutMs < 100 || timeoutMs > 5000) {
    fail('compare-timeout', { value: compare.timeoutMs });
  }
  if (!Number.isInteger(requiredSamples) || requiredSamples < 100) {
    fail('required-samples', { value: compare.requiredSamples });
  }
  const ignored = Array.isArray(compare.ignorePaths) ? compare.ignorePaths : [];
  if (ignored.length > 20
      || ignored.some((value) => typeof value !== 'string' || !value.startsWith('/'))) {
    fail('ignore-paths', { value: ignored });
  }

  const normalized = {
    version: 1,
    mode: text(input.mode, 20),
    writeMode: text(input.writeMode, 20),
    routePlanHash: text(input.routePlanHash, 64).toLowerCase(),
    cells: {
      a: {
        id: aId,
        host: aHost,
        role: text(a.role, 20),
        failureDomain: aDomain,
        dataRoot: aRoot,
        baseUrl: aUrl ? aUrl.toString().replace(/\/+$/, '') : ''
      },
      b: {
        id: bId,
        host: bHost,
        role: text(b.role, 20),
        failureDomain: bDomain,
        dataRoot: bRoot,
        baseUrl: bUrl ? bUrl.toString().replace(/\/+$/, '') : ''
      }
    },
    traffic: {
      sampleRate,
      maxRequestsPerSecond,
      readOnly: traffic.readOnly === true,
      writeMirror: traffic.writeMirror === true
    },
    compare: {
      timeoutMs,
      requiredSamples,
      ignorePaths: ignored.slice().sort()
    }
  };
  return {
    ok: failures.length === 0,
    failures,
    plan: normalized,
    hash: hash(normalized)
  };
}

module.exports = {
  validateDualCellPlan
};
