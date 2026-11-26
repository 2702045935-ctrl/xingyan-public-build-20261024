#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { buildPhysicalScalePlan } = require('../lib/physical-scale-plan');

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const row = process.argv.slice(2).find((value) => value.startsWith(prefix));
  return row ? row.slice(prefix.length) : fallback;
}

function main() {
  const sourceFile = arg('source', '');
  const targetFile = arg('target', '');
  if (!sourceFile || !targetFile) {
    throw new Error('usage: physical-scale-plan.js --source=FILE --target=FILE '
      + '[--out=FILE] [--require-eligible=1]');
  }
  const source = JSON.parse(fs.readFileSync(path.resolve(sourceFile), 'utf8'));
  const target = JSON.parse(fs.readFileSync(path.resolve(targetFile), 'utf8'));
  const report = buildPhysicalScalePlan(source, target, {
    maxShardMoves: Number(arg('max-shard-moves', '0')) || undefined,
    soakMinutes: Number(arg('soak-minutes', '30'))
  });
  const text = JSON.stringify(report, null, 2) + '\n';
  const out = arg('out', '');
  if (out) fs.writeFileSync(path.resolve(out), text, 'utf8');
  else process.stdout.write(text);
  if (!report.ok || (arg('require-eligible', '0') === '1'
      && report.productionEligible !== true)) {
    process.exitCode = 2;
  }
}

try {
  main();
} catch (error) {
  console.error(error.stack || error);
  process.exitCode = 1;
}
