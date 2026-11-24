'use strict';

const assert = require('assert');
const { spawnSync } = require('child_process');
const path = require('path');

function main() {
  const tool = path.join(__dirname, '..', 'tools', 'gateway-cluster-smoke.js');
  const result = spawnSync(process.execPath, [tool], {
    encoding: 'utf8',
    timeout: 60000
  });
  assert.equal(result.status, 0, result.stderr || result.stdout);
  const report = JSON.parse(result.stdout.trim().split('\n').pop());
  assert.equal(report.ok, true);
  assert.ok(report.liveNodes >= 2);
  console.log('gateway-cluster-smoke: passed');
}

main();
