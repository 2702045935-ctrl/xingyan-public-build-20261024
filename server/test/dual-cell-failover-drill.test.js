'use strict';

const assert = require('assert');
const { runDualCellFailoverDrill } = require('../lib/dual-cell-failover-drill');

const report = runDualCellFailoverDrill();
assert.strictEqual(report.ok, true, JSON.stringify(report, null, 2));
assert.strictEqual(report.okayToActivateTraffic, false);
assert.strictEqual(report.eventCount, 24);
assert.strictEqual(report.failures.length, 0);
for (const value of Object.values(report.checks)) {
  assert.strictEqual(value, true);
}
console.log('dual-cell-failover-drill: passed');
