#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { validateActiveDualCellPlan } = require('../lib/dual-cell-active-plan');

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const row = process.argv.slice(2).find((value) => value.startsWith(prefix));
  return row ? row.slice(prefix.length) : fallback;
}

function writeReport(report, out) {
  const text = JSON.stringify(report, null, 2);
  if (!out) {
    process.stdout.write(text);
    return;
  }
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
}

function main() {
  const planFile = arg('plan', '');
  if (!planFile) {
    throw new Error('usage: dual-cell-active-plan.js --plan=FILE [--out=REPORT]');
  }
  const plan = JSON.parse(fs.readFileSync(path.resolve(planFile), 'utf8'));
  const report = validateActiveDualCellPlan(plan);
  writeReport(report, arg('out', ''));
  if (!report.ok) process.exitCode = 2;
}

try {
  main();
} catch (error) {
  console.error(error.stack || error);
  process.exitCode = 1;
}
