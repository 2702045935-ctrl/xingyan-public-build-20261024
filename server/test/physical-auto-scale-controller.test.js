'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {
  evaluatePressure,
  PhysicalAutoScaleController
} = require('../lib/physical-auto-scale-controller');

const root = path.resolve(__dirname, '..', '..');
const source = JSON.parse(fs.readFileSync(
  path.join(root, 'deploy', 'fleet', 'fleet-production.json'),
  'utf8'
));

function targetPlan() {
  const plan = JSON.parse(JSON.stringify(source));
  plan.topologyId = 'auto-scale-4cell-rehearsal';
  plan.cells[0].ownerShards = [0, 1];
  plan.cells[0].failureDomain = 'provider-a-zone-a';
  plan.cells[1].ownerShards = [2, 3];
  plan.cells[1].failureDomain = 'provider-b-zone-a';
  plan.cells.push(cell('cell-c-auto', '192.0.2.30', 'provider-c-zone-a',
    'xingyan-dual-cell-c', [4, 5], 23080));
  plan.cells.push(cell('cell-d-auto', '192.0.2.31', 'provider-d-zone-a',
    'xingyan-dual-cell-d', [6], 24080));
  return plan;
}

function cell(id, host, failureDomain, servicePrefix, owners, basePort) {
  return {
    id,
    host,
    failureDomain,
    servicePrefix,
    dataRoot: '/opt/xingyan-dual-cell/physical-r1/stage/shards',
    replicaShards: [0, 1, 2, 3, 4, 5, 6],
    ownerShards: owners,
    ports: Array.from({ length: 7 }, (_, index) => basePort + index * 100)
  };
}

function adapters(log, failShard) {
  const noop = (name) => async (row) => {
    log.push(name + ':' + String(row.shard ?? row.cellId ?? ''));
    if (name === 'switchGateway' && row.shard === failShard && !row.rollback) {
      throw new Error('gateway failed');
    }
  };
  return {
    prepareNode: noop('prepareNode'),
    seedReplica: noop('seedReplica'),
    waitReplicaCaughtUp: noop('waitReplicaCaughtUp'),
    shadowRead: noop('shadowRead'),
    freezeOwner: noop('freezeOwner'),
    acquireLease: noop('acquireLease'),
    switchRoutes: noop('switchRoutes'),
    switchGateway: noop('switchGateway'),
    unfreezeOwner: noop('unfreezeOwner'),
    verifyOwner: noop('verifyOwner'),
    switchReplication: noop('switchReplication'),
    soak: async () => log.push('soak')
  };
}

function high() {
  return {
    cells: [{
      id: 'cell-a-43',
      ok: true,
      memoryUsedRatio: 0.9,
      loadPerCore: 0.95
    }]
  };
}

async function main() {
  assert.strictEqual(evaluatePressure(high()).pressured, true);
  let saved = {};
  let clock = 1000000;
  const log = [];
  const controller = new PhysicalAutoScaleController({
    targetPlanFor: async () => targetPlan(),
    adapters: adapters(log, -1),
    now: () => clock,
    loadState: async () => saved,
    saveState: async (value) => { saved = value; }
  });
  await controller.init();
  assert.strictEqual((await controller.runOnce(source, high())).reason,
    'pressure-warming');
  assert.strictEqual((await controller.runOnce(source, high())).reason,
    'pressure-warming');
  const result = await controller.runOnce(source, high());
  assert.strictEqual(result.ok, true, JSON.stringify(result));
  assert.strictEqual(log.filter((row) => row === 'soak').length, 1,
    JSON.stringify(log.slice(-20)));
  assert.strictEqual((await controller.runOnce(source, high())).reason, 'cooldown');

  clock += 2 * 60 * 60 * 1000;
  saved = {};
  const failLog = [];
  const failedController = new PhysicalAutoScaleController({
    targetPlanFor: async () => targetPlan(),
    adapters: adapters(failLog, 3),
    now: () => clock,
    loadState: async () => saved,
    saveState: async (value) => { saved = value; }
  });
  await failedController.init();
  for (let index = 0; index < 2; index += 1) {
    await failedController.runOnce(source, high());
  }
  const failed = await failedController.runOnce(source, high());
  assert.strictEqual(failed.ok, false);
  assert.strictEqual(failed.reason, 'cutover-failed');
  assert.ok(failed.events.some((row) => row.phase === 'rollback-complete'));

  console.log('physical-auto-scale-controller: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
