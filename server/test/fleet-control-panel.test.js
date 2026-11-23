'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { loadFleetControlPanel, controlStatus } = require('../lib/fleet-control-panel');

function write(file, value) {
  fs.writeFileSync(file, JSON.stringify(value, null, 2));
}

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-fleet-panel-'));
const configFile = path.join(dir, 'auto-scale.json');
const stateFile = path.join(dir, 'state.json');
const metricsFile = path.join(dir, 'metrics.json');
const auditFile = path.join(dir, 'audit.jsonl');
const failoverConfigFile = path.join(dir, 'failover.json');
const failoverStateFile = path.join(dir, 'failover-state.json');
const failoverAuditFile = path.join(dir, 'failover-audit.jsonl');
const fencingFile = path.join(dir, 'fencing.json');
write(configFile, { execute: true, intervalSeconds: 60, metricsMaxAgeSeconds: 180 });
write(stateFile, {
  busy: false,
  pressureStreak: 2,
  lastResult: { ok: true, reason: 'capacity-normal' }
});
write(metricsFile, {
  generatedAt: new Date().toISOString(),
  cells: [{
    id: 'cell-a', ok: true, memoryUsedRatio: 0.5, loadPerCore: 0.4,
    fdUtilization: 0.3, p99Ms: 120, diskUsedRatio: 0.6
  }]
});
fs.writeFileSync(auditFile,
  JSON.stringify({ ok: true, reason: 'complete', at: '2026-11-24T00:00:00Z' }) + '\n');
write(fencingFile, {
  ok: true,
  quorum: true,
  epoch: 7,
  expiresAt: Date.now() + 60_000
});
write(failoverConfigFile, {
  enabled: true,
  execute: true,
  fencingFile
});
write(failoverStateFile, {
  mode: 'failed-over',
  busy: false,
  activePlan: {
    version: 1,
    topologyId: 'active-failover',
    routePlanHash: 'a'.repeat(64),
    routePlanFileSha256: 'b'.repeat(64),
    shardCount: 1,
    release: { id: 'test', codeSha256: 'c'.repeat(64) },
    policy: {
      maxOwnerShardsInFlight: 1,
      requireReplicaCaughtUp: true,
      requireCapacityReport: true,
      requireHealthGate: true,
      autoRollback: true
    },
    cells: [{
      id: 'cell-b', host: '192.0.2.2',
      failureDomain: 'test-zone-b', servicePrefix: 'test-b',
      dataRoot: '/tmp/test-b', replicaShards: [0], ownerShards: [0], ports: [8080]
    }]
  },
  failedCellIds: ['cell-a'],
  failedOverAt: 1000,
  recoveryStreak: { 'cell-a': 2 },
  lastResult: { ok: true, reason: 'complete' }
});
fs.writeFileSync(failoverAuditFile,
  JSON.stringify({ ok: true, reason: 'complete', at: '2026-11-24T00:01:00Z' }) + '\n');

const panel = loadFleetControlPanel({
  configFile,
  stateFile,
  metricsFile,
  auditFile,
  failoverConfigFile,
  failoverStateFile,
  failoverAuditFile
});
assert.strictEqual(panel.control.status, 'healthy');
assert.strictEqual(panel.control.execute, true);
assert.strictEqual(panel.recentAudit.length, 1);
assert.strictEqual(panel.selfHealing.status, 'failed-over');
assert.strictEqual(panel.selfHealing.fencing.ready, true);
assert.strictEqual(panel.selfHealing.failedCellIds[0], 'cell-a');
assert.strictEqual(panel.selfHealing.activeTopologyId, 'active-failover');
assert.strictEqual(panel.selfHealing.recentAudit.length, 1);

const stale = controlStatus({
  config: { execute: true, metricsMaxAgeSeconds: 10 },
  state: {},
  metrics: { cells: [] },
  configFile,
  metricsFile: path.join(dir, 'missing.json')
});
assert.strictEqual(stale.status, 'blocked-stale');

const locked = controlStatus({
  config: { execute: true },
  state: {},
  metrics: { cells: [] },
  configFile,
  metricsFile,
  lockActive: true
});
assert.strictEqual(locked.status, 'running');

console.log('fleet-control-panel: passed');
