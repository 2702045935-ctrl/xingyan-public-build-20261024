'use strict';

const assert = require('assert');
const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const {
  validateFleetPlan,
  buildFleetReleasePlan
} = require('../lib/fleet-release-plan');

const root = path.resolve(__dirname, '..', '..');
const source = JSON.parse(fs.readFileSync(
  path.join(root, 'deploy', 'fleet', 'fleet-production.json'),
  'utf8'
));

function clone() {
  return JSON.parse(JSON.stringify(source));
}

function main() {
  const valid = validateFleetPlan(source);
  assert.strictEqual(valid.ok, true, JSON.stringify(valid.failures));
  assert.strictEqual(valid.deploymentEligible, false,
    'unverified provider failure domains must block production eligibility');
  assert.ok(valid.warnings.some((row) => row.code.endsWith('-failure-domain-unverified')));

  const plan = buildFleetReleasePlan(source, { canaryShard: 0 });
  assert.strictEqual(plan.shardCount, 7);
  assert.strictEqual(plan.cellCount, 2);
  assert.strictEqual(plan.deploymentEligible, false);
  assert.strictEqual(plan.stepCount, 14);
  assert.strictEqual(plan.steps.filter((step) => step.role === 'replica').length, 7);
  assert.strictEqual(plan.steps.filter((step) => step.role !== 'replica').length, 7);
  assert.strictEqual(plan.steps.find((step) => step.role === 'owner-canary').shardId, 0);
  assert.ok(plan.steps.findIndex((step) => step.role === 'replica')
    < plan.steps.findIndex((step) => step.role === 'owner-canary'),
  'replica releases must complete before the owner canary');
  assert.strictEqual(new Set(plan.steps.map((step) => step.wave)).size, plan.stepCount,
    'only one shard may be released in each wave');
  assert.ok(/^[a-f0-9]{64}$/.test(plan.planHash));

  const duplicateOwner = clone();
  duplicateOwner.cells[1].ownerShards.push(0);
  assert.ok(validateFleetPlan(duplicateOwner).failures.some((row) =>
    row.code === 'owner-coverage-0'));

  const duplicateHost = clone();
  duplicateHost.cells[1].host = duplicateHost.cells[0].host;
  assert.ok(validateFleetPlan(duplicateHost).failures.some((row) =>
    row.code === 'cell[1]-host-duplicate'));

  const missingReplica = clone();
  missingReplica.cells[0].replicaShards = [0, 1, 2, 3];
  assert.ok(validateFleetPlan(missingReplica).failures.some((row) =>
    row.code === 'cell[0]-replicas'));

  const unsafePolicy = clone();
  unsafePolicy.policy.maxOwnerShardsInFlight = 2;
  assert.ok(validateFleetPlan(unsafePolicy).failures.some((row) =>
    row.code === 'owner-concurrency'));

  const cli = spawnSync(process.execPath, [
    path.join(root, 'server', 'tools', 'fleet-release-plan.js'),
    '--plan=' + path.join(root, 'deploy', 'fleet', 'fleet-production.json'),
    '--require-eligible=1'
  ], { encoding: 'utf8', windowsHide: true });
  assert.strictEqual(cli.status, 2,
    'production execution must stop while failure domains remain unverified');

  console.log('fleet-release-plan: passed');
}

main();
