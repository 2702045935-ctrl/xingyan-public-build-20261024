#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { buildPhysicalScalePlan } = require('../lib/physical-scale-plan');
const { executePhysicalScale } = require('../lib/physical-scale-orchestrator');
const { validateFleetPlan } = require('../lib/fleet-release-plan');

const ROOT = path.resolve(__dirname, '..', '..');
const source = JSON.parse(fs.readFileSync(
  path.join(ROOT, 'deploy', 'fleet', 'fleet-production.json'), 'utf8'
));

function cell(id, host, domain, prefix, basePort) {
  return {
    id,
    host,
    failureDomain: domain,
    servicePrefix: prefix,
    dataRoot: '/opt/xingyan-dual-cell/physical-r1/stage/shards',
    replicaShards: [0, 1, 2, 3, 4, 5, 6],
    ownerShards: [],
    ports: Array.from({ length: 7 }, (_, shard) => basePort + shard * 100)
  };
}

function targetPlan() {
  const plan = JSON.parse(JSON.stringify(source));
  plan.topologyId = 'simulated-4cell';
  plan.cells[0].failureDomain = 'provider-a-zone-a';
  plan.cells[1].failureDomain = 'provider-b-zone-a';
  plan.cells.push(
    cell('cell-c', '192.0.2.70', 'provider-c-zone-a',
      'xingyan-dual-cell-c', 23080),
    cell('cell-d', '192.0.2.71', 'provider-d-zone-a',
      'xingyan-dual-cell-d', 24080)
  );
  const validation = validateFleetPlan(plan);
  if (!validation.ok) throw new Error(JSON.stringify(validation.failures));
  const owners = new Map();
  for (let shard = 0; shard < plan.shardCount; shard += 1) {
    const owner = validation.normalized.cells[shard % validation.normalized.cells.length];
    if (!owners.has(owner.id)) owners.set(owner.id, []);
    owners.get(owner.id).push(shard);
  }
  plan.cells.forEach((row) => {
    row.ownerShards = owners.get(row.id) || [];
  });
  const final = validateFleetPlan(plan);
  if (!final.ok || !final.deploymentEligible) {
    throw new Error(JSON.stringify(final.failures.concat(final.warnings)));
  }
  return plan;
}

function adapters(events, failAt) {
  const names = [
    'prepareNode', 'seedReplica', 'waitReplicaCaughtUp', 'shadowRead',
    'freezeOwner', 'acquireLease', 'switchRoutes', 'switchGateway',
    'unfreezeOwner', 'verifyOwner', 'switchReplication', 'soak'
  ];
  const out = {};
  for (const name of names) {
    out[name] = async (row) => {
      const event = {
        name,
        shard: row && row.shard,
        cellId: row && row.cellId,
        rollback: row && row.rollback === true
      };
      events.push(event);
      if (failAt && name === failAt.name
          && event.shard === failAt.shard && !event.rollback) {
        throw new Error('simulated-' + name + '-failure');
      }
      return { ok: true };
    };
  }
  return out;
}

async function main() {
  const target = targetPlan();
  const plan = buildPhysicalScalePlan(source, target, { soakMinutes: 1 });
  if (!plan.ok) throw new Error(JSON.stringify(plan.failures));

  const successEvents = [];
  const success = await executePhysicalScale(plan, adapters(successEvents), {
    retries: 1
  });

  const failureEvents = [];
  const failure = await executePhysicalScale(plan, adapters(failureEvents, {
    name: 'switchGateway',
    shard: 3
  }), { retries: 1 });

  const covered = target.cells.flatMap((row) => row.ownerShards)
    .sort((a, b) => a - b);
  const expected = Array.from({ length: 7 }, (_, index) => index);
  const report = {
    version: 1,
    generatedAt: new Date().toISOString(),
    scope: 'in-memory orchestration simulation; no production mutation',
    sourceCellCount: plan.sourceCellCount,
    targetCellCount: plan.targetCellCount,
    shardCount: target.shardCount,
    moveCount: plan.moves.length,
    planFingerprint: plan.fingerprint,
    targetOwnershipComplete:
      JSON.stringify(covered) === JSON.stringify(expected),
    success: {
      ok: success.ok,
      reason: success.reason,
      movedShards: success.movedShards,
      events: success.events
    },
    failureInjection: {
      ok: failure.ok,
      reason: failure.reason,
      failedShard: failure.failedShard,
      rolledBack: failure.events.some((row) =>
        row.phase === 'rollback-complete'),
      events: failure.events,
      adapterEvents: failureEvents
    },
    checks: {
      allMovesExecuted: success.ok
        && success.movedShards === plan.moves.length,
      replicationHandoff: successEvents.some((row) =>
        row.name === 'switchReplication' && !row.rollback),
      rollbackOrder: (() => {
        const tail = failureEvents.slice(
          failureEvents.findIndex((row) => row.rollback));
        const replication = tail.findIndex((row) =>
          row.name === 'switchReplication' && row.rollback);
        const routes = tail.findIndex((row) =>
          row.name === 'switchRoutes' && row.rollback);
        const gateway = tail.findIndex((row) =>
          row.name === 'switchGateway' && row.rollback);
        return routes >= 0 && routes < gateway
          && (replication < 0 || replication < routes);
      })()
    }
  };
  report.ok = report.success.ok
    && report.failureInjection.rolledBack
    && report.targetOwnershipComplete
    && Object.values(report.checks).every(Boolean);
  const out = process.argv.find((value) =>
    value.startsWith('--out='))?.slice(6);
  const text = JSON.stringify(report, null, 2) + '\n';
  if (out) fs.writeFileSync(path.resolve(out), text, 'utf8');
  else process.stdout.write(text);
  if (!report.ok) process.exitCode = 2;
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
