#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { collectSingleCellCapacity } = require('../lib/single-cell-capacity-collector');

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const row = process.argv.slice(2).find((value) => value.startsWith(prefix));
  return row ? row.slice(prefix.length) : fallback;
}

function main() {
  const manifest = arg('manifest', '/opt/xingyan-mainline/app/shard-runtime-production.json');
  const dataDir = arg('data-dir', '');
  const out = arg('out', '');
  if (!out) {
    throw new Error('usage: single-cell-capacity-collect.js '
      + '[--manifest=FILE] [--data-dir=DIR] --out=REPORT');
  }
  const report = collectSingleCellCapacity({ manifest, dataDir: dataDir || undefined });
  const file = path.resolve(out);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temporary = file + '.' + process.pid + '.tmp';
  fs.writeFileSync(temporary, JSON.stringify(report, null, 2), 'utf8');
  fs.renameSync(temporary, file);
  console.log(JSON.stringify({
    ok: report.ok,
    failures: report.failures.map((row) => row.code)
      .concat(report.audit.failures.map((row) => row.code)),
    fingerprint: report.audit.fingerprint,
    out: file
  }, null, 2));
  if (!report.ok) process.exitCode = 2;
}

try {
  main();
} catch (error) {
  console.error(error.stack || error);
  process.exitCode = 1;
}
