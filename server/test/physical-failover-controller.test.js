'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {
  buildFailbackPlan,
  PhysicalFailoverController
} = require('../lib/physical-failover-controller');
const { validateFleetPlan } = require('../lib/fleet-release-plan');

const root = path.resolve(__dirname, '..', '..');
const baseline = JSON.parse(fs.readFileSync(
  path.join(root, 'deploy', 'fleet', 'fleet-production.json'),
  'utf8'
));

function metrics(a, b) {
  return {
    generatedAt: new Date().toISOString(),
    cells: [
      { id: 'cell-a-43', ok: a },
      { id: 'cell-b-192', ok: b }
    ]
  };
}

function adapters(log, options) {
  const opts = options || {};
  const noop = (name) => async (move) => {
    log.push(name + ':' + move.shard + ':' + (move.rollback === true ? 'rollback' : 'forward'));
    if (name === 'switchGateway'
        && move.shard === opts.failGatewayShard
        && move.rollback !== true) {
      throw new Error('gateway switch failed');
    }
  };
  return {
    waitReplicaCaughtUp: noop('waitReplicaCaughtUp'),
    shadowRead: noop('shadowRead'),
    acquireLease: noop('acquireLease'),
    switchRoutes: noop('switchRoutes'),
    switchGateway: noop('switchGateway'),
    unfreezeOwner: noop('unfreezeOwner'),
    verifyOwner: noop('verifyOwner'),
    switchReplication: noop('switchReplication'),
    soak: async () => log.push('soak')
  };
}

function createController(overrides) {
  const opts = overrides || {};
  const log = opts.log || [];
  let saved = opts.saved || {};
  const controller = new PhysicalFailoverController({
    baselinePlan: baseline,
    policy: Object.assign({
      failureSamples: 3,
      recoverySamples: 6,
      failbackCooldownSeconds: 300,
      retries: 1
    }, opts.policy || {}),
    now: opts.now || (() => Date.now()),
    fencingReady: opts.fencingReady || (async () => true),
    adapterFactory: opts.adapterFactory || (async () => adapters(log, opts.adapterOptions)),
    loadState: async () => saved,
    saveState: async (value) => { saved = value; }
  });
  return { controller, log, state: () => saved };
}

function assertSingleOwner(plan) {
  const validation = validateFleetPlan(plan);
  assert.strictEqual(validation.ok, true, JSON.stringify(validation.failures));
  for (let shard = 0; shard < plan.shardCount; shard += 1) {
    const owners = plan.cells.filter((cell) => cell.ownerShards.includes(shard));
    assert.strictEqual(owners.length, 1, 'shard ' + shard + ' has ' + owners.length);
  }
}

async function main() {
  let clock = 1_000_000;
  const blocked = createController({
    now: () => clock,
    fencingReady: async () => false
  });
  await blocked.controller.init();
  await blocked.controller.runOnce(metrics(false, true));
  await blocked.controller.runOnce(metrics(false, true));
  const blockedResult = await blocked.controller.runOnce(metrics(false, true));
  assert.strictEqual(blockedResult.ok, false);
  assert.strictEqual(blockedResult.reason, 'fencing-not-ready');
  assert.strictEqual(blocked.controller.state.mode, 'normal');
  assert.strictEqual(blocked.controller.state.busy, false);

  const takeover = createController({ now: () => clock });
  await takeover.controller.init();
  await takeover.controller.runOnce(metrics(false, true));
  await takeover.controller.runOnce(metrics(false, true));
  const taken = await takeover.controller.runOnce(metrics(false, true));
  assert.strictEqual(taken.ok, true, JSON.stringify(taken));
  assert.strictEqual(takeover.controller.state.mode, 'failed-over');
  assert.deepStrictEqual(takeover.controller.state.failedCellIds, ['cell-a-43']);
  assertSingleOwner(takeover.controller.state.activePlan);
  assert.ok(takeover.log.includes('switchGateway:0:forward'));
  assert.ok(takeover.log.includes('switchReplication:3:forward'));

  clock += 301_000;
  for (let index = 0; index < 5; index += 1) {
    const waiting = await takeover.controller.runOnce(metrics(true, true));
    assert.strictEqual(waiting.reason, 'waiting-failback');
  }
  const failback = await takeover.controller.runOnce(metrics(true, true));
  assert.strictEqual(failback.ok, true, JSON.stringify(failback));
  assert.strictEqual(takeover.controller.state.mode, 'normal');
  assertSingleOwner(takeover.controller.state.activePlan);
  assert.strictEqual(
    takeover.controller.state.activePlan.topologyId,
    baseline.topologyId
  );
  assert.ok(takeover.log.includes('switchGateway:0:forward'));
  assert.strictEqual(takeover.controller.state.busy, false);

  const rollbackLog = [];
  const failedClock = clock + 10_000_000;
  const failed = createController({
    log: rollbackLog,
    now: () => failedClock,
    adapterOptions: { failGatewayShard: 2 }
  });
  await failed.controller.init();
  await failed.controller.runOnce(metrics(false, true));
  await failed.controller.runOnce(metrics(false, true));
  const rolledBack = await failed.controller.runOnce(metrics(false, true));
  assert.strictEqual(rolledBack.ok, false);
  assert.strictEqual(rolledBack.reason, 'failover-failed');
  assert.ok(rolledBack.events.some((row) => row.phase === 'rollback-complete'));
  assert.strictEqual(failed.controller.state.mode, 'normal');
  assert.strictEqual(failed.controller.state.busy, false);
  assertSingleOwner(failed.controller.state.activePlan);
  assert.strictEqual(
    failed.controller.state.activePlan.topologyId,
    baseline.topologyId
  );

  const crashed = createController({
    now: () => failedClock,
    adapterFactory: async () => { throw new Error('adapter assembly failed'); }
  });
  await crashed.controller.init();
  await crashed.controller.runOnce(metrics(false, true));
  await crashed.controller.runOnce(metrics(false, true));
  const crashedResult = await crashed.controller.runOnce(metrics(false, true));
  assert.strictEqual(crashedResult.ok, false);
  assert.strictEqual(crashedResult.reason, 'failover-execution-error');
  assert.strictEqual(crashed.controller.state.busy, false);

  const failbackPlan = buildFailbackPlan(
    takeover.state().activePlan || baseline,
    baseline
  );
  assert.strictEqual(failbackPlan.ok, false);
  assert.strictEqual(failbackPlan.reason, 'already-at-baseline');

  console.log('physical-failover-controller: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
