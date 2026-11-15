'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-reliability-probe-test-'));
const outputFile = path.join(root, 'probe.json');

try {
  const result = spawnSync(process.execPath, [
    path.join(__dirname, '..', 'tools', 'message-reliability-probe.js'),
    '--workers', '4',
    '--per-worker', '25',
    '--out', outputFile
  ], {
    encoding: 'utf8',
    windowsHide: true
  });
  assert.strictEqual(result.status, 0, result.stderr || result.stdout);
  const report = JSON.parse(fs.readFileSync(outputFile, 'utf8'));
  assert.strictEqual(report.ok, true);
  assert.strictEqual(report.scope, 'system-temporary-directory');
  assert.strictEqual(report.workers, 4);
  assert.strictEqual(report.expectedMessages, 100);
  assert.strictEqual(report.messages, 100);
  assert.strictEqual(report.events, 100);
  assert.strictEqual(report.maxSeq, 100);
  assert.strictEqual(report.contiguous, true);
  assert.strictEqual(report.sequenceCount, 100);
  assert.strictEqual(report.firstSequence, 1);
  assert.strictEqual(report.lastSequence, 100);
  assert.match(report.sequenceDigest, /^[a-f0-9]{64}$/);
  assert.strictEqual(report.sequences, undefined);

  console.log('message-reliability-probe: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
