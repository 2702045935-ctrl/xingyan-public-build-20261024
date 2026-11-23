'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { buildPhysicalScalePlan } = require('../lib/physical-scale-plan');
const { executePhysicalScale } = require('../lib/physical-scale-orchestrator');

const root = path.resolve(__dirname, '..', '..');
const source = JSON.parse(fs.readFileSync(
  path.join(root, 'deploy', 'fleet', 'fleet-production.json'),
  'utf8'
));

function targetPlan() {
  const plan = JSON.parse(JSON.stringify(source));
  plan.topologyId = 'physical-scale-orchestrator-4cell';
  plan.cells[0].ownerShards = [0, 1];
  plan.cells[0].failureDomain = 'provider-a-zone-a';
  plan.cells[1].ownerShards = [2, 3];
  plan.cells[1].failureDomain = 'provider-b-zone-a';
  plan.cells.push(
    cell('cell-c-orchestrator', '192.0.2.20', 'provider-c-zone-a',
      'xingyan-dual-cell-c', [4, 5], 21080),
    cell('cell-d-orchestrator', '192.0.2.21', 'provider-d-zone-a',
      'xingyan-dual-cell-d', [6], 22080)
  );
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

function adapters(log, failGatewayForShard) {
  const noop = (name) => async (row) => {
    log.push(name + ':' + String(row.shard ?? row.cellId ?? ''));
    if (name === 'switchGateway'
        && row.shard === failGatewayForShard && !row.rollback) {
      throw new Error('gateway switch failed');
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
    soak: async () => log.push('soak')
  };
}

async function main() {
  const plan = buildPhysicalScalePlan(source, targetPlan(), { soakMinutes: 30 });
  assert.strictEqual(plan.ok, true, JSON.stringify(plan.failures));

  const successLog = [];
  const success = await executePhysicalScale(plan, adapters(successLog, -1));
  assert.strictEqual(success.ok, true, JSON.stringify(success.events));
  assert.strictEqual(success.movedShards, 5);
  assert.strictEqual(successLog.filter((row) => row.startsWith('soak')).length, 1);
  assert.strictEqual(successLog.filter((row) =>
    row === 'switchGateway:2').length, 1);

  const failLog = [];
  const failed = await executePhysicalScale(plan, adapters(failLog, 3));
  assert.strictEqual(failed.ok, false);
  assert.strictEqual(failed.reason, 'cutover-failed');
  assert.ok(failLog.includes('switchGateway:3'));
  assert.ok(failLog.includes('switchRoutes:3'));
  assert.ok(failLog.includes('acquireLease:3'));
  assert.ok(failLog.includes('unfreezeOwner:3'));
  assert.ok(failed.events.some((row) => row.phase === 'rollback-complete'));

  console.log('physical-scale-orchestrator: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
