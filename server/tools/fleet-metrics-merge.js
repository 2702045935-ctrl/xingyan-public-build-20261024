#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { buildFleetMetrics } = require('../lib/fleet-metrics');

function rows(name) {
  const prefix = '--' + name + '=';
  return process.argv.slice(2).filter((value) => value.startsWith(prefix))
    .map((value) => value.slice(prefix.length));
}

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const value = process.argv.slice(2).find((item) => item.startsWith(prefix));
  return value ? value.slice(prefix.length) : fallback;
}

function atomicJson(file, value) {
  const target = path.resolve(file);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  const temporary = target + '.' + process.pid + '.tmp';
  fs.writeFileSync(temporary, JSON.stringify(value, null, 2) + '\n');
  fs.renameSync(temporary, target);
}

function main() {
  const latency = new Map(rows('latency').map((value) => {
    const index = value.indexOf(':');
    if (index <= 0) throw new Error('latency must be cellId:ms');
    return [value.slice(0, index), Number(value.slice(index + 1))];
  }));
  const inputs = rows('cell').map((value) => {
    const index = value.indexOf(':');
    if (index <= 0) throw new Error('cell must be cellId:report.json');
    const cellId = value.slice(0, index);
    return {
      cellId,
      input: JSON.parse(fs.readFileSync(path.resolve(value.slice(index + 1)), 'utf8')),
      p99Ms: latency.get(cellId) || 0
    };
  });
  if (!inputs.length) throw new Error('at least one --cell=CELL:REPORT is required');
  const result = buildFleetMetrics(inputs, {
    fdLimit: Number(arg('fd-limit', '65536'))
  });
  const out = arg('out', '');
  if (out) atomicJson(out, result);
  else process.stdout.write(JSON.stringify(result, null, 2) + '\n');
}

try {
  main();
} catch (error) {
  process.stderr.write(String(error && error.stack || error) + '\n');
  process.exitCode = 1;
}
