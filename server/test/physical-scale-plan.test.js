'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { buildPhysicalScalePlan } = require('../lib/physical-scale-plan');

const root = path.resolve(__dirname, '..', '..');
const source = JSON.parse(fs.readFileSync(
  path.join(root, 'deploy', 'fleet', 'fleet-production.json'),
  'utf8'
));

function targetPlan() {
  const plan = JSON.parse(JSON.stringify(source));
  plan.topologyId = 'physical-scale-4cell-rehearsal';
  plan.cells[0].ownerShards = [0, 1];
  plan.cells[0].failureDomain = 'provider-a-zone-a';
  plan.cells[1].ownerShards = [2, 3];
  plan.cells[1].failureDomain = 'provider-b-zone-a';
  plan.cells.push({
    id: 'cell-c-rehearsal',
    host: '192.0.2.10',
    failureDomain: 'provider-c-zone-a',
    servicePrefix: 'xingyan-dual-cell-c',
    dataRoot: '/opt/xingyan-dual-cell/physical-r1/stage/shards',
    replicaShards: [0, 1, 2, 3, 4, 5, 6],
    ownerShards: [4, 5],
    ports: [21080, 21180, 21280, 21380, 21480, 21580, 21680]
  });
  plan.cells.push({
    id: 'cell-d-rehearsal',
    host: '192.0.2.11',
    failureDomain: 'provider-d-zone-a',
    servicePrefix: 'xingyan-dual-cell-d',
    dataRoot: '/opt/xingyan-dual-cell/physical-r1/stage/shards',
    replicaShards: [0, 1, 2, 3, 4, 5, 6],
    ownerShards: [6],
    ports: [22080, 22180, 22280, 22380, 22480, 22580, 22680]
  });
  return plan;
}

const report = buildPhysicalScalePlan(source, targetPlan(), {
  soakMinutes: 30
});
assert.strictEqual(report.ok, true, JSON.stringify(report.failures));
assert.strictEqual(report.sourceCellCount, 2);
assert.strictEqual(report.targetCellCount, 4);
assert.strictEqual(report.addedCellCount, 2);
assert.strictEqual(report.moveCount, 5);
assert.strictEqual(report.productionEligible, true);
assert.match(report.fingerprint, /^[a-f0-9]{64}$/);
assert.deepStrictEqual(
  Array.from(new Set(report.stages.map((row) => row.stage))),
  ['prepare-node', 'seed-replica', 'catch-up', 'shadow-read', 'cutover', 'soak']
);
assert.ok(report.stages.filter((row) => row.stage === 'cutover')
  .every((row) => row.steps.indexOf('freeze-old-owner-writes')
    < row.steps.indexOf('switch-gateway-mapping')));
assert.ok(report.stages.filter((row) => row.stage === 'cutover')
  .every((row) => row.rollback.includes('unfreeze-old-owner')));

const unsafe = JSON.parse(JSON.stringify(source));
unsafe.cells[0].ownerShards = [0, 1, 2, 3, 4, 5, 6];
unsafe.cells[1].ownerShards = [0];
const rejected = buildPhysicalScalePlan(source, unsafe);
assert.strictEqual(rejected.ok, false);
assert.ok(rejected.failures.length > 0);

console.log('physical-scale-plan: passed');
