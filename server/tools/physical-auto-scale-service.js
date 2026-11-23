#!/usr/bin/env node
'use strict';

const path = require('path');
const { PhysicalAutoScaleRuntime } = require('../lib/physical-auto-scale-runtime');

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const row = process.argv.slice(2).find((value) => value.startsWith(prefix));
  return row ? row.slice(prefix.length) : fallback;
}

async function main() {
  const configFile = arg('config', '');
  if (!configFile) throw new Error('usage: physical-auto-scale-service.js --config=FILE');
  if (process.argv.includes('--check')) {
    const runtime = new PhysicalAutoScaleRuntime({ configFile });
    const source = runtime.plan(runtime.config.sourcePlanFile);
    const target = runtime.config.targetPlanFile
      ? runtime.plan(runtime.config.targetPlanFile)
      : null;
    process.stdout.write(JSON.stringify({
      ok: true,
      execute: runtime.config.execute,
      sourceTopology: source.topologyId,
      targetTopology: target && target.topologyId,
      targetEligible: target ? target.deploymentEligible : false
    }) + '\n');
    return;
  }
  const runtime = new PhysicalAutoScaleRuntime({ configFile });
  if (process.argv.includes('--once')) {
    const result = await runtime.runOnce();
    process.stdout.write(JSON.stringify(result) + '\n');
    if (!result.ok) process.exitCode = 2;
    return;
  }
  runtime.start((error, result) => {
    const row = error
      ? { at: new Date().toISOString(), ok: false, error: error.message }
      : result;
    process.stdout.write(JSON.stringify(row) + '\n');
  });
  process.on('SIGTERM', () => runtime.stop());
  process.on('SIGINT', () => runtime.stop());
}

main().catch((error) => {
  process.stderr.write(String(error && error.stack || error) + '\n');
  process.exitCode = 1;
});
