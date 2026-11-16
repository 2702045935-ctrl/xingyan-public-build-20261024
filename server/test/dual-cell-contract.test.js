'use strict';

const assert = require('assert');
const { validateDualCellPlan } = require('../lib/dual-cell-contract');

const valid = {
  version: 1,
  mode: 'shadow',
  writeMode: 'disabled',
  routePlanHash: 'a'.repeat(64),
  cells: {
    a: {
      id: 'cn-a',
      host: '10.0.0.10',
      role: 'primary',
      failureDomain: 'az-a',
      dataRoot: '/data/cell-a'
    },
    b: {
      id: 'cn-b',
      host: '10.0.0.20',
      role: 'shadow',
      failureDomain: 'az-b',
      dataRoot: '/data/cell-b'
    }
  },
  traffic: {
    sampleRate: 0.01,
    maxRequestsPerSecond: 50,
    readOnly: true,
    writeMirror: false
  },
  compare: {
    timeoutMs: 800,
    requiredSamples: 10000,
    ignorePaths: ['/data/time', '/data/requestId']
  }
};

const accepted = validateDualCellPlan(valid);
assert.strictEqual(accepted.ok, true, JSON.stringify(accepted.failures));
assert.match(accepted.hash, /^[a-f0-9]{64}$/);

const sameHost = JSON.parse(JSON.stringify(valid));
sameHost.cells.b.host = valid.cells.a.host;
assert.ok(validateDualCellPlan(sameHost).failures.some(
  (row) => row.code === 'cell-host-shared'
));

const nestedData = JSON.parse(JSON.stringify(valid));
nestedData.cells.b.dataRoot = '/data/cell-a/shadow';
assert.ok(validateDualCellPlan(nestedData).failures.some(
  (row) => row.code === 'cell-data-root-overlap'
));

const sameFailureDomain = JSON.parse(JSON.stringify(valid));
sameFailureDomain.cells.b.failureDomain = 'az-a';
assert.ok(validateDualCellPlan(sameFailureDomain).failures.some(
  (row) => row.code === 'failure-domain-shared'
));

const writeMirror = JSON.parse(JSON.stringify(valid));
writeMirror.traffic.writeMirror = true;
assert.ok(validateDualCellPlan(writeMirror).failures.some(
  (row) => row.code === 'traffic-write-mirror'
));

const highSample = JSON.parse(JSON.stringify(valid));
highSample.traffic.sampleRate = 0.5;
assert.ok(validateDualCellPlan(highSample).failures.some(
  (row) => row.code === 'sample-rate'
));

console.log('dual-cell-contract: passed');
