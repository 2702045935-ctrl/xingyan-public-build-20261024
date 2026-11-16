'use strict';

const assert = require('assert');
const { EventEmitter } = require('events');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { runSingleCellCapacityCollector } = require('../lib/single-cell-capacity-runner');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-capacity-runner-'));
const tool = path.join(root, 'collect.js');
const manifest = path.join(root, 'manifest.json');
const dataDir = path.join(root, 'data');
const out = path.join(root, 'report.json');
fs.writeFileSync(tool, '');
fs.writeFileSync(manifest, '{}');
fs.mkdirSync(dataDir);

function fakeSpawn() {
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.kill = () => {};
  queueMicrotask(() => {
    fs.writeFileSync(out, JSON.stringify({ ok: true, fingerprint: 'a'.repeat(64) }));
    child.stdout.emit('data', Buffer.from('{"ok":true}'));
    child.emit('exit', 0);
  });
  return child;
}

async function main() {
  const result = await runSingleCellCapacityCollector({
    tool,
    manifest,
    dataDir,
    out,
    spawnImpl: fakeSpawn
  });
  assert.strictEqual(result.code, 0);
  assert.strictEqual(result.report.ok, true);
  assert.strictEqual(fs.existsSync(out), false);

  const badOut = path.join(root, 'bad.json');
  const badSpawn = () => {
    const child = new EventEmitter();
    child.stdout = new EventEmitter();
    child.stderr = new EventEmitter();
    child.kill = () => {};
    queueMicrotask(() => child.emit('exit', 1));
    return child;
  };
  await assert.rejects(() => runSingleCellCapacityCollector({
    tool,
    manifest,
    dataDir,
    out: badOut,
    spawnImpl: badSpawn
  }), /produced no valid report/);

  console.log('single-cell-capacity-runner: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
}).finally(() => {
  fs.rmSync(root, { recursive: true, force: true });
});
