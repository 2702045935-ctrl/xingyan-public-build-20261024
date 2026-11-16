#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { verifyPhysicalLayout } = require('../lib/shard-physical-layout');

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const row = process.argv.slice(2).find((value) => value.startsWith(prefix));
  return row ? row.slice(prefix.length) : fallback;
}

function main() {
  const root = arg('root', '');
  const routePlanFile = arg('route-plan', '');
  const out = arg('out', '');
  if (!root || !routePlanFile) {
    throw new Error('usage: shard-physical-layout-audit.js '
      + '--root=PHYSICAL_ROOT --route-plan=FILE [--out=REPORT]');
  }
  const routePlan = JSON.parse(fs.readFileSync(path.resolve(routePlanFile), 'utf8'));
  const report = verifyPhysicalLayout({ root, routePlan });
  const text = JSON.stringify(report, null, 2);
  if (out) {
    const file = path.resolve(out);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const temporary = file + '.' + process.pid + '.tmp';
    fs.writeFileSync(temporary, text, 'utf8');
    fs.renameSync(temporary, file);
    console.log(JSON.stringify({
      ok: report.ok,
      hash: report.hash,
      failures: report.failures.length,
      out: file
    }, null, 2));
  } else {
    process.stdout.write(text);
  }
  if (!report.ok) process.exitCode = 1;
}

try {
  main();
} catch (error) {
  console.error(error.stack || error);
  process.exitCode = 1;
}
