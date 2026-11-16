#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { validateDualCellPlan } = require('../lib/dual-cell-contract');

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const row = process.argv.slice(2).find((value) => value.startsWith(prefix));
  return row ? row.slice(prefix.length) : fallback;
}

function main() {
  const planFile = arg('plan', '');
  const out = arg('out', '');
  if (!planFile) throw new Error('usage: dual-cell-contract.js --plan=FILE [--out=REPORT]');
  const report = validateDualCellPlan(JSON.parse(fs.readFileSync(path.resolve(planFile), 'utf8')));
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
      failures: report.failures,
      out: file
    }, null, 2));
  } else {
    process.stdout.write(text);
  }
  if (!report.ok) process.exitCode = 2;
}

try {
  main();
} catch (error) {
  console.error(error.stack || error);
  process.exitCode = 1;
}
