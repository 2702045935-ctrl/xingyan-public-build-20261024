#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { evaluateSingleCellCapacity } = require('../lib/single-cell-capacity');

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const row = process.argv.slice(2).find((value) => value.startsWith(prefix));
  return row ? row.slice(prefix.length) : fallback;
}

function main() {
  const inputFile = arg('input', '');
  const out = arg('out', '');
  if (!inputFile) {
    throw new Error('usage: single-cell-capacity-audit.js --input=FILE [--out=REPORT]');
  }
  const input = JSON.parse(fs.readFileSync(path.resolve(inputFile), 'utf8'));
  const report = evaluateSingleCellCapacity(input, input.policy || {});
  const text = JSON.stringify(report, null, 2);
  if (out) {
    const file = path.resolve(out);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const temporary = file + '.' + process.pid + '.tmp';
    fs.writeFileSync(temporary, text, 'utf8');
    fs.renameSync(temporary, file);
    console.log(JSON.stringify({
      ok: report.ok,
      failures: report.failures.map((row) => row.code),
      fingerprint: report.fingerprint,
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
