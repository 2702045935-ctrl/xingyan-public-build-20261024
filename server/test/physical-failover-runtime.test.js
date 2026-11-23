'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const {
  PhysicalFailoverRuntime,
  fencingStatus
} = require('../lib/physical-failover-runtime');

const root = path.resolve(__dirname, '..', '..');
const baseline = JSON.parse(fs.readFileSync(
  path.join(root, 'deploy', 'fleet', 'fleet-production.json'),
  'utf8'
));
baseline.cells[0].failureDomain = 'provider-a-zone-a';
baseline.cells[1].failureDomain = 'provider-b-zone-a';
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-failover-runtime-'));
const planFile = path.join(dir, 'plan.json');
const metricsFile = path.join(dir, 'metrics.json');
const fencingFile = path.join(dir, 'fencing.json');
fs.writeFileSync(planFile, JSON.stringify(baseline));

function writeMetrics(a, b) {
  fs.writeFileSync(metricsFile, JSON.stringify({
    version: 1,
    generatedAt: new Date().toISOString(),
    cells: [
      { id: 'cell-a-43', ok: a },
      { id: 'cell-b-192', ok: b }
    ]
  }));
}

function config(extra) {
  return Object.assign({
    enabled: true,
    execute: true,
    metricsMaxAgeSeconds: 180,
    planFile,
    metricsFile,
    stateFile: path.join(dir, 'state.json'),
    auditFile: path.join(dir, 'audit.jsonl'),
    fencingFile
  }, extra || {});
}

function adapters(log) {
  const noop = (name) => async (move) => {
    log.push(name + ':' + move.shard);
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

async function main() {
  try {
    writeMetrics(true, true);
    const disabled = new PhysicalFailoverRuntime({
      config: config({ enabled: false, execute: false })
    });
    assert.strictEqual((await disabled.runOnce()).reason, 'execution-disabled');

    const noFencing = new PhysicalFailoverRuntime({
      config: config(),
      fencingReady: async () => false
    });
    writeMetrics(false, true);
    await noFencing.runOnce();
    await noFencing.runOnce();
    const blocked = await noFencing.runOnce();
    assert.strictEqual(blocked.reason, 'fencing-not-ready');

    const auditFile = path.join(dir, 'audit-ok.jsonl');
    const stateFile = path.join(dir, 'state-ok.json');
    const log = [];
    const runtime = new PhysicalFailoverRuntime({
      config: config({ auditFile, stateFile }),
      fencingReady: async () => true,
      adapterFactory: async () => adapters(log)
    });
    writeMetrics(false, true);
    await runtime.runOnce();
    await runtime.runOnce();
    const result = await runtime.runOnce();
    assert.strictEqual(result.ok, true, JSON.stringify(result));
    assert.strictEqual(log.filter((row) => row === 'soak').length, 1);
    assert.ok(fs.existsSync(auditFile));
    const state = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
    assert.strictEqual(state.mode, 'failed-over');
    assert.strictEqual(state.busy, false);

    const now = 10_000;
    fs.writeFileSync(fencingFile, JSON.stringify({
      ok: true,
      quorum: true,
      epoch: 2,
      expiresAt: now + 10_000
    }));
    assert.strictEqual(fencingStatus(fencingFile, now).ok, true);
    assert.strictEqual(fencingStatus(fencingFile, now + 20_000).reason,
      'fencing-expired');
    fs.writeFileSync(fencingFile, JSON.stringify({
      ok: true,
      quorum: false,
      epoch: 2,
      expiresAt: now + 10_000
    }));
    assert.strictEqual(fencingStatus(fencingFile, now).reason,
      'fencing-quorum-lost');

    console.log('physical-failover-runtime: passed');
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
