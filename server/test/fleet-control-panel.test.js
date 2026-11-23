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

const panel = loadFleetControlPanel({
  configFile, stateFile, metricsFile, auditFile
});
assert.strictEqual(panel.control.status, 'healthy');
assert.strictEqual(panel.control.execute, true);
assert.strictEqual(panel.recentAudit.length, 1);

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
