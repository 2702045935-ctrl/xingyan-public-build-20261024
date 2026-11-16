'use strict';

const assert = require('assert');
const { runDualCellShadowProbe } = require('../lib/dual-cell-shadow-probe');
const { validateDualCellPlan } = require('../lib/dual-cell-contract');

const plan = {
  version: 1,
  mode: 'shadow',
  writeMode: 'disabled',
  routePlanHash: 'a'.repeat(64),
  cells: {
    a: {
      id: 'cell-a',
      host: 'cell-a.example',
      role: 'primary',
      failureDomain: 'az-a',
      dataRoot: '/data/cell-a',
      baseUrl: 'https://cell-a.example:5443'
    },
    b: {
      id: 'cell-b',
      host: 'cell-b.example',
      role: 'shadow',
      failureDomain: 'az-b',
      dataRoot: '/data/cell-b',
      baseUrl: 'https://cell-b.example:5443'
    }
  },
  traffic: {
    sampleRate: 0.1,
    maxRequestsPerSecond: 1000,
    readOnly: true,
    writeMirror: false
  },
  compare: {
    timeoutMs: 500,
    requiredSamples: 100,
    ignorePaths: ['/data/time']
  }
};
const requests = Array.from({ length: 100 }, (_, index) => ({
  method: 'GET',
  path: '/api/users/u' + index
}));

function response(body, status) {
  return {
    status: status || 200,
    headers: { get: () => 'application/json' },
    text: async () => JSON.stringify(body)
  };
}

async function main() {
  const fetchImpl = async (url) => response({
    ok: true,
    data: {
      path: new URL(url).pathname,
      time: url.includes('cell-a') ? 'time-a' : 'time-b'
    }
  });
  let report = await runDualCellShadowProbe({
    plan,
    requests,
    fetchImpl,
    sampler: () => true,
    sleep: async () => {}
  });
  assert.strictEqual(report.ok, true, JSON.stringify({ diffs: report.diffs, errors: report.errors }));
  assert.strictEqual(report.compared, 100);
  assert.strictEqual(report.diffs.length, 0);
  assert.match(report.fingerprint, /^[a-f0-9]{64}$/);

  report = await runDualCellShadowProbe({
    plan,
    requests,
    fetchImpl: async (url) => response({
      ok: true,
      data: {
        path: new URL(url).pathname,
        value: url.includes('cell-a') ? 'A' : 'B',
        time: 'ignored'
      }
    }),
    sampler: () => true,
    sleep: async () => {}
  });
  assert.strictEqual(report.ok, false);
  assert.strictEqual(report.diffs.length, 100);

  const lowSampleContract = validateDualCellPlan(plan);
  lowSampleContract.plan.compare.requiredSamples = 1;
  let calls = 0;
  report = await runDualCellShadowProbe({
    contract: lowSampleContract,
    requests: requests.slice(0, 10),
    fetchImpl: async (url) => {
      calls += 1;
      if (url.includes('cell-b')) throw new Error('timeout');
      return response({ ok: true });
    },
    sampler: () => true,
    sleep: async () => {}
  });
  assert.strictEqual(report.circuitOpen, true);
  assert.ok(calls < 23);
  assert.ok(report.errors.length >= 3);

  report = await runDualCellShadowProbe({
    plan,
    requests: [{ method: 'POST', path: '/api/write' }],
    fetchImpl,
    sampler: () => true
  });
  assert.strictEqual(report.ok, false);
  assert.deepStrictEqual(report.methodViolations, ['/api/write']);

  console.log('dual-cell-shadow-probe: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
