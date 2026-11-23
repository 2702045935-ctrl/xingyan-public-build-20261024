#!/usr/bin/env node
'use strict';

const { PhysicalFailoverRuntime } = require('../lib/physical-failover-runtime');

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const row = process.argv.slice(2).find((value) => value.startsWith(prefix));
  return row ? row.slice(prefix.length) : fallback;
}

async function main() {
  const configFile = arg('config', '');
  if (!configFile) {
    throw new Error('usage: physical-failover-service.js --config=FILE');
  }
  const runtime = new PhysicalFailoverRuntime({ configFile });
  if (process.argv.includes('--check')) {
    const plan = runtime.plan();
    const fencing = runtime.fencingReady();
    process.stdout.write(JSON.stringify({
      ok: true,
      enabled: runtime.config.enabled === true,
      execute: runtime.config.execute === true,
      topologyId: plan.topologyId,
      deploymentEligible: plan.deploymentEligible,
      fencingReady: fencing === true
    }) + '\n');
    return;
  }
  if (process.argv.includes('--once')) {
    const result = await runtime.runOnce();
    process.stdout.write(JSON.stringify(result) + '\n');
    if (result.ok === false) process.exitCode = 2;
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
