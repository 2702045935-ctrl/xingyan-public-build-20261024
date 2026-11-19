#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const {
  validateFleetPlan,
  buildFleetReleasePlan
} = require('../lib/fleet-release-plan');

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const row = process.argv.slice(2).find((value) => value.startsWith(prefix));
  return row ? row.slice(prefix.length) : fallback;
}

function main() {
  const inputFile = arg('plan', '');
  const outFile = arg('out', '');
  const canaryShard = Number(arg('canary-shard', '0'));
  const requireEligible = arg('require-eligible', '0') === '1';
  if (!inputFile) {
    throw new Error('usage: fleet-release-plan.js --plan=FILE [--canary-shard=N] [--out=FILE]');
  }
  const input = JSON.parse(fs.readFileSync(path.resolve(inputFile), 'utf8'));
  const validation = validateFleetPlan(input);
  if (!validation.ok) {
    console.error(JSON.stringify({ ok: false, failures: validation.failures }, null, 2));
    process.exitCode = 1;
    return;
  }
  const plan = buildFleetReleasePlan(input, { canaryShard });
  const text = JSON.stringify(plan, null, 2) + '\n';
  if (outFile) {
    fs.writeFileSync(path.resolve(outFile), text, 'utf8');
  } else {
    process.stdout.write(text);
  }
  if (requireEligible && !plan.deploymentEligible) {
    console.error('fleet release is not production eligible: resolve all warnings first');
    process.exitCode = 2;
  }
}

try {
  main();
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    error: String(error && error.message || error),
    failures: error && error.failures || []
  }, null, 2));
  process.exitCode = 1;
}
