#!/usr/bin/env node
'use strict';

const { PhysicalMigrationRuntime } = require('../lib/physical-migration-runtime');

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const row = process.argv.slice(2).find((value) => value.startsWith(prefix));
  return row ? row.slice(prefix.length) : fallback;
}

async function main() {
  const configFile = arg('config', '');
  if (!configFile) {
    throw new Error('usage: physical-migration-service.js --config=FILE');
  }
  const runtime = new PhysicalMigrationRuntime({ configFile });
  if (process.argv.includes('--check')) {
    process.stdout.write(JSON.stringify({
      ok: true,
      allowExplicitMigration: runtime.config.allowExplicitMigration === true,
      promoteOnSuccess: runtime.config.promoteOnSuccess === true
    }) + '\n');
    return;
  }
  if (process.argv.includes('--once')) {
    const result = await runtime.runOnce();
    process.stdout.write(JSON.stringify(result) + '\n');
    if (result.ok === false) process.exitCode = 2;
    return;
  }
  const interval = Math.max(2,
    Number(runtime.config.workerIntervalSeconds) || 5) * 1000;
  let running = false;
  let timer = null;
  const tick = async () => {
    if (running) return;
    running = true;
    try {
      const result = await runtime.runOnce();
      if (result.reason !== 'no-migration-request') {
        process.stdout.write(JSON.stringify(result) + '\n');
      }
    } catch (error) {
      process.stderr.write(JSON.stringify({
        at: new Date().toISOString(),
        ok: false,
        error: String(error && error.message || error)
      }) + '\n');
    } finally {
      running = false;
    }
  };
  timer = setInterval(tick, interval);
  await tick();
  process.on('SIGTERM', () => clearInterval(timer));
  process.on('SIGINT', () => clearInterval(timer));
}

main().catch((error) => {
  process.stderr.write(String(error && error.stack || error) + '\n');
  process.exitCode = 1;
});
