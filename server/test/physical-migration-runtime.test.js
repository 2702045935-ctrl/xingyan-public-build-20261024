'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const {
  PhysicalMigrationRuntime
} = require('../lib/physical-migration-runtime');
const {
  addNode,
  deleteNode
} = require('../lib/fleet-plan-mutation');

const root = path.resolve(__dirname, '..', '..');
const source = JSON.parse(fs.readFileSync(
  path.join(root, 'deploy', 'fleet', 'fleet-production.json'),
  'utf8'
));
source.cells[0].failureDomain = 'provider-a-zone-a';
source.cells[1].failureDomain = 'provider-b-zone-a';

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-migration-runtime-'));
const sourceFile = path.join(dir, 'source.json');
const targetFile = path.join(dir, 'target.json');
const requestFile = path.join(dir, 'request.json');
const stateFile = path.join(dir, 'state.json');
const auditFile = path.join(dir, 'audit.jsonl');
fs.writeFileSync(sourceFile, JSON.stringify(source, null, 2));

function adapters(log) {
  const noop = (name) => async (row) => {
    log.push(name + ':' + (row.shard ?? row.id ?? row.cellId ?? ''));
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
    decommissionNode: noop('decommissionNode'),
    soak: async () => log.push('soak')
  };
}

async function main() {
  try {
    const log = [];
    const runtime = new PhysicalMigrationRuntime({
      config: {
        allowExplicitMigration: true,
        promoteOnSuccess: true,
        soakMinutes: 1,
        sourcePlanFile: sourceFile,
        targetPlanFile: targetFile,
        requestFile,
        stateFile,
        auditFile
      },
      adapterFactory: async () => adapters(log)
    });
    const expanded = addNode(source, {
      id: 'cell-c-203',
      host: '192.0.2.30',
      failureDomain: 'provider-c-zone-a',
      servicePrefix: 'xingyan-dual-cell-c',
      dataRoot: '/opt/xingyan-dual-cell/physical-r1/stage/shards',
      ports: [21080, 21180, 21280, 21380, 21480, 21580, 21680]
    });
    const queued = await runtime.submit({
      plan: expanded,
      actor: { username: 'admin' }
    });
    assert.strictEqual(queued.ok, true, JSON.stringify(queued));
    const scaledOut = await runtime.runOnce();
    assert.strictEqual(scaledOut.ok, true, JSON.stringify(scaledOut));
    assert.strictEqual(scaledOut.status, 'completed');
    assert.ok(log.some((row) => row.startsWith('prepareNode:cell-c-203')));
    assert.strictEqual(
      JSON.parse(fs.readFileSync(sourceFile, 'utf8')).cells.length,
      3
    );
    const repeated = await runtime.runOnce();
    assert.strictEqual(repeated.reason, 'completed');

    const current = JSON.parse(fs.readFileSync(sourceFile, 'utf8'));
    const shrunk = deleteNode(current, 'cell-c-203');
    const removeQueued = await runtime.submit({ plan: shrunk });
    assert.strictEqual(removeQueued.ok, true, JSON.stringify(removeQueued));
    const scaledIn = await runtime.runOnce();
    assert.strictEqual(scaledIn.ok, true, JSON.stringify(scaledIn));
    assert.ok(log.some((row) => row.startsWith('decommissionNode:cell-c-203')));
    assert.strictEqual(
      JSON.parse(fs.readFileSync(sourceFile, 'utf8')).cells.length,
      2
    );
    assert.ok(fs.existsSync(auditFile));

    console.log('physical-migration-runtime: passed');
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
