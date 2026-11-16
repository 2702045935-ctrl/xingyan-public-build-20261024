#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { rehearseShardPlacement } = require('../lib/shard-placement-rehearsal');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(path.resolve(file), 'utf8'));
}

function main() {
  const sourceDir = arg('source');
  const routePlan = arg('route-plan');
  const stageDir = arg('stage');
  const rehydrateDir = arg('rehydrate');
  const out = arg('out');
  if (!sourceDir || !routePlan || !stageDir || !rehydrateDir || !out) {
    throw new Error('usage: shard-placement-rehearsal.js --source DIR '
      + '--route-plan FILE --stage DIR --rehydrate DIR --out FILE '
      + '[--thread-limit N]');
  }
  const report = rehearseShardPlacement({
    sourceDir,
    stageDir,
    rehydrateDir,
    routePlan: readJson(routePlan),
    threadLimit: Number(arg('thread-limit', '0')) || 0
  });
  const file = path.resolve(out);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file + '.tmp', JSON.stringify(report, null, 2), 'utf8');
  fs.renameSync(file + '.tmp', file);
  console.log(JSON.stringify({
    ok: report.ok,
    counts: report.counts,
    failures: report.failures,
    out: file
  }, null, 2));
  if (!report.ok) process.exitCode = 2;
}

if (require.main === module) {
  try { main(); }
  catch (error) {
    console.error(error.stack || error);
    process.exitCode = 1;
  }
}

module.exports = { main };
