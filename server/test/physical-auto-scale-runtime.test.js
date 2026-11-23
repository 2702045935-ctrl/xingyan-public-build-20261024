'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { PhysicalAutoScaleRuntime } = require('../lib/physical-auto-scale-runtime');
const { buildFleetMetrics } = require('../lib/fleet-metrics');

const root = path.resolve(__dirname, '..', '..');
const source = JSON.parse(fs.readFileSync(
  path.join(root, 'deploy', 'fleet', 'fleet-production.json'), 'utf8'
));

function target() {
  const plan = JSON.parse(JSON.stringify(source));
  plan.topologyId = 'runtime-4cell';
  plan.cells[0].ownerShards = [0, 1];
  plan.cells[0].failureDomain = 'provider-a-zone-a';
  plan.cells[1].ownerShards = [2, 3];
  plan.cells[1].failureDomain = 'provider-b-zone-a';
  plan.cells.push(
    cell('cell-c', '192.0.2.50', 'provider-c-zone-a',
      'xingyan-dual-cell-c', [4, 5], 23080),
    cell('cell-d', '192.0.2.51', 'provider-d-zone-a',
      'xingyan-dual-cell-d', [6], 24080)
  );
  return plan;
}

function cell(id, host, domain, prefix, owners, basePort) {
  return {
    id, host, failureDomain: domain, servicePrefix: prefix,
    dataRoot: '/opt/xingyan-dual-cell/physical-r1/stage/shards',
    replicaShards: [0, 1, 2, 3, 4, 5, 6],
    ownerShards: owners,
    ports: Array.from({ length: 7 }, (_, shard) => basePort + shard * 100)
  };
}

function adapters(log) {
  const noop = (name) => async () => { log.push(name); return { ok: true }; };
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
    soak: noop('soak')
  };
}

function write(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(value, null, 2));
}

async function main() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-auto-scale-runtime-'));
  const files = {
    source: path.join(dir, 'source.json'),
    target: path.join(dir, 'target.json'),
    metrics: path.join(dir, 'metrics.json'),
    state: path.join(dir, 'state.json'),
    audit: path.join(dir, 'audit.jsonl')
  };
  write(files.source, source);
  write(files.target, target());
  write(files.metrics, buildFleetMetrics([{
    cellId: 'cell-a-43',
    p99Ms: 2100,
    input: {
      ok: true,
      input: {
        host: {
          cpuCount: 8,
          load1: 7.8,
          totalMemoryBytes: 100,
          freeMemoryBytes: 10,
          disk: { totalBytes: 100, freeBytes: 10 }
        },
        shards: [{ fdCount: 60000 }]
      }
    }
  }]));
  const log = [];
  const runtime = new PhysicalAutoScaleRuntime({
    config: {
      execute: true,
      promoteOnSuccess: true,
      intervalSeconds: 60,
      sourcePlanFile: files.source,
      targetPlanFile: files.target,
      metricsFile: files.metrics,
      stateFile: files.state,
      auditFile: files.audit,
      lockFile: path.join(dir, 'scale.lock'),
      targetPlanMaxAgeSeconds: 86400,
      metricsMaxAgeSeconds: 180,
      policy: { windowSamples: 3, cooldownMinutes: 60 }
    },
    adapterFactory: async () => adapters(log)
  });
  assert.strictEqual((await runtime.runOnce()).reason, 'pressure-warming');
  assert.strictEqual((await runtime.runOnce()).reason, 'pressure-warming');
  const completed = await runtime.runOnce();
  assert.strictEqual(completed.ok, true, JSON.stringify(completed));
  assert.strictEqual(JSON.parse(fs.readFileSync(files.source, 'utf8')).topologyId,
    'runtime-4cell');
  assert.ok(fs.readFileSync(files.audit, 'utf8').includes('"reason":"complete"'));
  assert.ok(log.includes('switchGateway'));

  fs.writeFileSync(path.join(dir, 'scale.lock'), '{"pid":1}');
  const lockedRuntime = new PhysicalAutoScaleRuntime({
    config: Object.assign({}, runtime.config, {
      stateFile: files.state,
      lockFile: path.join(dir, 'scale.lock')
    }),
    adapterFactory: async () => adapters(log)
  });
  assert.strictEqual((await lockedRuntime.runOnce()).reason, 'scale-job-locked');

  const disabled = new PhysicalAutoScaleRuntime({
    config: Object.assign({}, runtime.config, {
      execute: false,
      targetPlanFile: files.target,
      lockFile: path.join(dir, 'disabled.lock')
    })
  });
  assert.strictEqual((await disabled.runOnce()).reason, 'execution-disabled');

  const expansionSource = path.join(dir, 'expansion-source.json');
  write(expansionSource, source);
  const expansion = new PhysicalAutoScaleRuntime({
    config: {
      execute: false,
      sourcePlanFile: expansionSource,
      metricsFile: files.metrics,
      stateFile: path.join(dir, 'expansion-state.json'),
      auditFile: path.join(dir, 'expansion-audit.jsonl'),
      lockFile: path.join(dir, 'expansion.lock'),
      expansion: {
        topologyId: 'runtime-generated-4cell',
        verifiedDomains: {
          'cell-a-43': 'provider-a-zone-a',
          'cell-b-192': 'provider-b-zone-a'
        },
        additions: [
          cell('cell-c', '192.0.2.52', 'provider-c-zone-a',
            'xingyan-dual-cell-c', [4, 5], 23080),
          cell('cell-d', '192.0.2.53', 'provider-d-zone-a',
            'xingyan-dual-cell-d', [6], 24080)
        ].map((row) => Object.assign(row, { ownerShards: undefined }))
      }
    }
  });
  assert.strictEqual((await expansion.runOnce()).reason, 'execution-disabled');
  console.log('physical-auto-scale-runtime: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
