'use strict';

const crypto = require('crypto');
const { validateDualCellPlan } = require('./dual-cell-contract');

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

function pointerParts(pointer) {
  return String(pointer || '').split('/').slice(1)
    .map((part) => part.replace(/~1/g, '/').replace(/~0/g, '~'));
}

function removePointer(value, pointer) {
  const parts = pointerParts(pointer);
  if (!parts.length) return;
  let target = value;
  for (let index = 0; index < parts.length - 1; index += 1) {
    if (!target || typeof target !== 'object') return;
    target = target[parts[index]];
  }
  if (target && typeof target === 'object') delete target[parts[parts.length - 1]];
}

function normalizePayload(value, ignored) {
  let copy;
  try { copy = JSON.parse(JSON.stringify(value)); }
  catch (_) { copy = value; }
  for (const pointer of ignored || []) removePointer(copy, pointer);
  return copy;
}

async function readResponse(response) {
  const text = await response.text();
  let body = text;
  const type = String(response.headers && response.headers.get
    ? response.headers.get('content-type') || ''
    : '');
  if (type.includes('json') || /^[\s]*[\[{]/.test(text)) {
    try { body = JSON.parse(text); } catch (_) { body = text; }
  }
  return { status: response.status, body };
}

async function oneRequest(options) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), options.timeoutMs);
  const started = Date.now();
  try {
    const response = await options.fetchImpl(options.url, {
      method: options.method,
      headers: options.headers,
      signal: controller.signal,
      redirect: 'manual'
    });
    const value = await readResponse(response);
    return {
      ok: true,
      latencyMs: Date.now() - started,
      status: value.status,
      body: normalizePayload(value.body, options.ignorePaths)
    };
  } catch (error) {
    return {
      ok: false,
      latencyMs: Date.now() - started,
      error: String(error && error.name || error && error.message || error)
    };
  } finally {
    clearTimeout(timer);
  }
}

async function runDualCellShadowProbe(options) {
  const opts = options || {};
  const contract = opts.contract || validateDualCellPlan(opts.plan);
  const requests = Array.isArray(opts.requests) ? opts.requests : [];
  const methodErrors = requests.filter((row) =>
    !['GET', 'HEAD'].includes(String(row && row.method || 'GET').toUpperCase())
  );
  if (!contract.ok || methodErrors.length) {
    return {
      version: 1,
      readOnly: true,
      ok: false,
      planHash: contract.hash || '',
      contractFailures: contract.failures || [],
      methodViolations: methodErrors.map((row) => String(row && row.path || '')),
      compared: 0,
      diffs: [],
      errors: []
    };
  }
  const fetchImpl = opts.fetchImpl || fetch;
  const sampler = opts.sampler || (() => Math.random() < contract.plan.traffic.sampleRate);
  const sleep = opts.sleep || ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
  const minInterval = 1000 / contract.plan.traffic.maxRequestsPerSecond;
  const results = [];
  let lastStarted = 0;
  let consecutiveBErrors = 0;
  let circuitOpen = false;
  let attempted = 0;
  let sampled = 0;

  for (let index = 0; index < requests.length; index += 1) {
    const request = requests[index];
    if (!sampler(index, request)) continue;
    sampled += 1;
    const wait = Math.max(0, lastStarted + minInterval - Date.now());
    if (wait > 0) await sleep(wait);
    lastStarted = Date.now();
    attempted += 1;
    const method = String(request.method || 'GET').toUpperCase();
    const pathname = String(request.path || '');
    if (!pathname.startsWith('/')) {
      results.push({
        index,
        path: pathname,
        compared: false,
        error: 'invalid-path'
      });
      continue;
    }
    const ignored = (contract.plan.compare.ignorePaths || [])
      .concat(Array.isArray(request.ignorePaths) ? request.ignorePaths : []);
    const headersA = Object.assign({
      Accept: 'application/json'
    }, opts.headersA || {}, request.headersA || {});
    const headersB = Object.assign({
      Accept: 'application/json'
    }, opts.headersB || {}, request.headersB || {});
    const a = await oneRequest({
      url: contract.plan.cells.a.baseUrl + pathname,
      method,
      headers: headersA,
      timeoutMs: contract.plan.compare.timeoutMs,
      ignorePaths: ignored,
      fetchImpl
    });
    let b = null;
    if (!circuitOpen) {
      b = await oneRequest({
        url: contract.plan.cells.b.baseUrl + pathname,
        method,
        headers: headersB,
        timeoutMs: contract.plan.compare.timeoutMs,
        ignorePaths: ignored,
        fetchImpl
      });
      if (!b.ok) {
        consecutiveBErrors += 1;
        if (consecutiveBErrors >= 3) circuitOpen = true;
      } else {
        consecutiveBErrors = 0;
      }
    }
    const compared = !!(a.ok && b && b.ok);
    const equal = compared
      && a.status === b.status
      && stable(a.body) === stable(b.body);
    results.push({
      index,
      method,
      path: pathname,
      compared,
      equal,
      a,
      b,
      circuitOpen
    });
  }

  const diffs = results.filter((row) => row.compared && !row.equal).map((row) => ({
    index: row.index,
    path: row.path,
    aStatus: row.a.status,
    bStatus: row.b.status,
    aHash: hash(row.a.body),
    bHash: hash(row.b.body)
  }));
  const errors = results.filter((row) => !row.compared).map((row) => ({
    index: row.index,
    path: row.path,
    aError: row.a && row.a.ok ? '' : row.a && row.a.error || 'missing-a',
    bError: row.b && row.b.ok ? '' : row.b && row.b.error || (circuitOpen
      ? 'circuit-open'
      : 'missing-b')
  }));
  const compared = results.filter((row) => row.compared).length;
  const requiredSamples = contract.plan.compare.requiredSamples;
  const deterministic = {
    version: 1,
    planHash: contract.hash,
    routePlanHash: contract.plan.routePlanHash,
    sampled,
    attempted,
    compared,
    diffHash: hash(diffs),
    errorHash: hash(errors)
  };
  return Object.assign({
    readOnly: true,
    ok: diffs.length === 0
      && errors.length === 0
      && compared >= requiredSamples
      && !circuitOpen,
    requiredSamples,
    sampleTargetMet: compared >= requiredSamples,
    circuitOpen,
    diffs: diffs.slice(0, 1000),
    errors: errors.slice(0, 1000),
    results: results.slice(0, 1000),
    fingerprint: hash(deterministic)
  }, deterministic);
}

module.exports = {
  runDualCellShadowProbe
};
