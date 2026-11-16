#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { switchWriteFreeze } = require('../lib/shard-write-freeze');

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const row = process.argv.slice(2).find((value) => value.startsWith(prefix));
  return row ? row.slice(prefix.length) : fallback;
}

async function main() {
  const freeze = process.argv.includes('--freeze');
  const unfreeze = process.argv.includes('--unfreeze');
  if (freeze === unfreeze) throw new Error('use exactly one of --freeze or --unfreeze');
  const ports = String(arg('ports', '7080,7180,7280,7380,7480,7580,7680'))
    .split(',').map(Number);
  const out = arg('out', '');
  const report = await switchWriteFreeze({
    ports,
    frozen: freeze,
    reason: arg('reason', 'physical-shard-cutover'),
    secretFile: arg('secret-file', '/opt/xingyan-mainline/data/secret.key'),
    planFile: arg('plan-file', '/opt/xingyan-mainline/releases/20261116-shard-baseline/route-plan.json')
  });
  const text = JSON.stringify(report, null, 2);
  if (out) {
    const file = path.resolve(out);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const temporary = file + '.' + process.pid + '.tmp';
    fs.writeFileSync(temporary, text, 'utf8');
    fs.renameSync(temporary, file);
  }
  console.log(JSON.stringify({
    ok: report.ok,
    frozen: report.frozen,
    fenceEpoch: report.fenceEpoch,
    planHash: report.planHash,
    ports: report.ports,
    out: out ? path.resolve(out) : ''
  }, null, 2));
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
