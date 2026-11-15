#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { buildShardRebalancePlan } = require('../lib/shard-rebalance-plan');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function writeJson(file, value) {
  const target = path.resolve(file);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  const temporary = target + '.' + process.pid + '.tmp';
  fs.writeFileSync(temporary, JSON.stringify(value, null, 2), 'utf8');
  fs.renameSync(temporary, target);
  return target;
}

function main() {
  const routePlanFile = arg('route-plan');
  const targetShards = Number(arg('target-shards'));
  const targetTopology = arg('target-topology');
  if (!routePlanFile || !Number.isInteger(targetShards) || !targetTopology) {
    throw new Error('usage: shard-rebalance-plan.js --route-plan FILE '
      + '--target-shards N --target-topology ID [--out FILE] '
      + '[--assignments-out FILE] [--moves-out FILE]');
  }
  const routePlan = JSON.parse(fs.readFileSync(path.resolve(routePlanFile), 'utf8'));
  const report = buildShardRebalancePlan({
    sourceShardCount: routePlan.shardCount,
    targetShardCount: targetShards,
    targetTopologyId: targetTopology,
    assignments: routePlan.assignments
  });
  const assignmentsOut = arg('assignments-out');
  const movesOut = arg('moves-out');
  if (assignmentsOut) writeJson(assignmentsOut, report.assignments || {});
  if (movesOut) writeJson(movesOut, report.moves || []);
  const summary = Object.assign({}, report);
  delete summary.assignments;
  delete summary.moves;
  const out = arg('out');
  if (out) {
    const file = writeJson(out, summary);
    console.log(JSON.stringify({
      ok: summary.ok,
      sourceShardCount: summary.sourceShardCount,
      targetShardCount: summary.targetShardCount,
      moveCount: summary.moveCount,
      movePct: summary.movePct,
      maxDeviation: summary.maxDeviation,
      fingerprint: summary.fingerprint,
      out: file
    }, null, 2));
  } else {
    process.stdout.write(JSON.stringify(summary, null, 2));
  }
  if (!summary.ok) process.exitCode = 2;
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    console.error(error.stack || error);
    process.exitCode = 1;
  }
}

module.exports = { main };
