'use strict';

const assert = require('assert');
const { runShardFaultDrill } = require('../lib/shard-fault-drill');

const report = runShardFaultDrill();
assert.strictEqual(report.ok, true, JSON.stringify(report, null, 2));
assert.strictEqual(report.scope, 'system-temporary-directory');
assert.strictEqual(report.topologyId, 'drill-shards-7');
assert.strictEqual(report.leaseEpochB, 2);
assert.strictEqual(report.repair.repaired, 1);
assert.strictEqual(report.repair.events, 3);
assert.deepStrictEqual(report.eventIds, [
  'drill-event-1',
  'drill-event-2',
  'drill-event-3'
]);
for (const value of Object.values(report.checks)) {
  assert.strictEqual(value, true);
}

console.log('shard-fault-drill: passed');
