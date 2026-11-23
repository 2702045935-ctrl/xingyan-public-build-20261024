'use strict';

const assert = require('assert');
const {
  buildNodeProvisionPlan
} = require('../lib/fleet-node-provision');

const input = {
  cellId: 'cell-c-203',
  sourceHost: '192.0.2.10',
  sourceUser: 'root',
  sourceRoot: '/opt/xingyan-dual-cell/release-r1',
  releaseRoot: '/opt/xingyan-dual-cell/release-r1',
  dataRoot: '/opt/xingyan-dual-cell/physical-r1/stage/shards',
  servicePrefix: 'xingyan-dual-cell-c',
  envFile: '/etc/xingyan-dual-cell/xingyan-dual-cell-c.env',
  unitFile: '/etc/systemd/system/xingyan-dual-cell-c@.service',
  shardCount: 7,
  ports: [21080, 21180, 21280, 21380, 21480, 21580, 21680],
  ownerPorts: [17080, 17180, 15499, 15599, 19480, 19580, 19680],
  ownedShards: [],
  routePlan: '/opt/xingyan-dual-cell/route-plan.json',
  routePlanSha256: 'a'.repeat(64),
  routeSourceFile: '/opt/xingyan-dual-cell/route-plan.json',
  secretFile: '/opt/xingyan-dual-cell/key-domain/secret.key',
  secretSourceFile: '/opt/xingyan-dual-cell/key-domain/secret.key',
  fleetPlan: '/etc/xingyan-dual-cell/current-fleet.json',
  nodeBin: '/opt/node24/bin/node',
  busAddr: '127.0.0.1:16400'
};

const plan = buildNodeProvisionPlan(input);
assert.strictEqual(plan.cellId, 'cell-c-203');
assert.strictEqual(plan.fingerprint.length, 64);
assert.ok(plan.env.includes('DUAL_CELL_ID=cell-c-203'));
assert.ok(plan.env.includes('DUAL_CELL_SHARD_PORTS=21080,21180,21280,21380,21480,21580,21680'));
assert.ok(plan.env.includes('DUAL_CELL_FLEET_PLAN=/etc/xingyan-dual-cell/current-fleet.json'));
assert.ok(plan.environment === undefined);
assert.ok(plan.unit.includes(
  'ExecStart=/opt/xingyan-dual-cell/release-r1/run-dual-cell-shard.sh %i'
));
assert.ok(plan.unit.includes(
  'EnvironmentFile=/etc/xingyan-dual-cell/xingyan-dual-cell-c.env'
));

assert.throws(() => buildNodeProvisionPlan(Object.assign({}, input, {
  cellId: 'bad\ncell'
})), /unsafe characters/);
assert.throws(() => buildNodeProvisionPlan(Object.assign({}, input, {
  dataRoot: '/opt/../escape'
})), /absolute safe path/);
assert.throws(() => buildNodeProvisionPlan(Object.assign({}, input, {
  ports: [1, 2, 3]
})), /one positive port per shard/);

console.log('fleet-node-provision: passed');
