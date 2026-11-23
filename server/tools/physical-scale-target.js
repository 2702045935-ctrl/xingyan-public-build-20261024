#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { buildExpandedFleetPlan } = require('../lib/physical-scale-target');

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const row = process.argv.slice(2).find((value) => value.startsWith(prefix));
  return row ? row.slice(prefix.length) : fallback;
}

function atomicJson(file, value) {
  const target = path.resolve(file);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  const temporary = target + '.' + process.pid + '.tmp';
  fs.writeFileSync(temporary, JSON.stringify(value, null, 2) + '\n');
  fs.renameSync(temporary, target);
}

try {
  const sourceFile = arg('source', '');
  const additionsFile = arg('additions', '');
  const out = arg('out', '');
  if (!sourceFile || !additionsFile || !out) {
    throw new Error('usage: physical-scale-target.js --source=FILE '
      + '--additions=FILE --out=FILE [--topology=ID]');
  }
  const input = JSON.parse(fs.readFileSync(path.resolve(sourceFile), 'utf8'));
  const additions = JSON.parse(fs.readFileSync(path.resolve(additionsFile), 'utf8'));
  const result = buildExpandedFleetPlan(input,
    Array.isArray(additions) ? additions : additions.cells,
    {
      topologyId: arg('topology', ''),
      verifiedDomains: additions.verifiedDomains || {}
    });
  atomicJson(out, result);
  process.stdout.write(JSON.stringify({
    ok: true,
    topologyId: result.topologyId,
    cells: result.cells.length,
    deploymentEligible: result.deploymentEligible
  }) + '\n');
} catch (error) {
  process.stderr.write(String(error && error.stack || error) + '\n');
  process.exitCode = 1;
}
