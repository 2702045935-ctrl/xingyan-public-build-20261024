'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const {
  createPhysicalScaleProductionAdapters
} = require('../lib/physical-scale-production-adapters');
const { buildPhysicalScalePlan } = require('../lib/physical-scale-plan');
const { executePhysicalScale } = require('../lib/physical-scale-orchestrator');

const root = path.resolve(__dirname, '..', '..');
const source = JSON.parse(fs.readFileSync(
  path.join(root, 'deploy', 'fleet', 'fleet-production.json'), 'utf8'
));

function cell(id, host, domain, prefix, owners, basePort) {
  return {
    id,
    host,
    failureDomain: domain,
    servicePrefix: prefix,
    dataRoot: '/opt/xingyan-dual-cell/physical-r1/stage/shards',
    replicaShards: [0, 1, 2, 3, 4, 5, 6],
    ownerShards: owners,
    ports: Array.from({ length: 7 }, (_, shard) => basePort + shard * 100)
  };
}

function target() {
  const plan = JSON.parse(JSON.stringify(source));
  plan.topologyId = 'production-adapters-4cell';
  plan.cells[0].ownerShards = [0, 1];
  plan.cells[0].failureDomain = 'provider-a-zone-a';
  plan.cells[1].ownerShards = [2, 3];
  plan.cells[1].failureDomain = 'provider-b-zone-a';
  plan.cells.push(
    cell('cell-c', '192.0.2.40', 'provider-c-zone-a',
      'xingyan-dual-cell-c', [4, 5], 23080),
    cell('cell-d', '192.0.2.41', 'provider-d-zone-a',
      'xingyan-dual-cell-d', [6], 24080)
  );
  return plan;
}

async function main() {
  const routeBytes = Buffer.from(JSON.stringify({
    version: 1,
    hash: 'a'.repeat(64),
    shardCount: 7,
    assignments: {}
  }));
  const routeSha = crypto.createHash('sha256').update(routeBytes).digest('hex');
  const calls = [];
  const runner = {
    async run(request) {
      const payload = JSON.parse(Buffer.from(request.argv[3], 'base64').toString('utf8'));
      calls.push({ host: request.host, action: request.purpose, payload });
      if (request.purpose === 'manifest') {
        return { ok: true, hash: 'manifest-ok', files: 3 };
      }
      if (request.purpose === 'freeze-one') {
        return { ok: true, frozen: true, fenceEpoch: 2 };
      }
      if (request.purpose === 'unfreeze-one') {
        return { ok: true, frozen: false, fenceEpoch: 3 };
      }
      if (request.purpose === 'reload-gateway') {
        return { ok: true, reloadMode: 'SIGHUP' };
      }
      if (request.purpose === 'write-fleet-plan') {
        return { ok: true, sha256: payload.sha256 };
      }
      return { ok: true };
    }
  };
  const adapters = createPhysicalScaleProductionAdapters({
    sourcePlan: source,
    targetPlan: target(),
    runner,
    routePlan: { hash: 'a'.repeat(64), fileSha256: routeSha, bytes: routeBytes },
    gateway: {
      host: '43.242.194.89',
      service: 'xingyan-dual-cell-tls-live',
      healthPort: 5443
    },
    soakDurationMs: 1
  });
  const plan = buildPhysicalScalePlan(source, target(), { soakMinutes: 1 });
  assert.strictEqual(plan.ok, true, JSON.stringify(plan.failures));
  const result = await executePhysicalScale(plan, adapters, { retries: 1 });
  assert.strictEqual(result.ok, true, JSON.stringify(result.events));
  const staging = calls.find((row) => row.action === 'write-gateway-routing');
  assert.deepStrictEqual(staging.payload.ownerPorts, [
    17080, 17180, 15499, 15599, 23480, 23580, 24680
  ]);
  assert.deepStrictEqual(staging.payload.ownerTargets, [
    'http://43.242.194.89:17080',
    'http://43.242.194.89:17180',
    'http://192.140.179.176:15499',
    'http://192.140.179.176:15599',
    'http://192.0.2.40:23480',
    'http://192.0.2.40:23580',
    'http://192.0.2.41:24680'
  ]);
  assert.ok(calls.some((row) => row.action === 'reload-gateway'));
  assert.ok(calls.some((row) => row.action === 'write-fleet-plan'));
  assert.ok(!calls.some((row) => row.action === 'restart'));

  const provisionCalls = [];
  const provisioningAdapters = createPhysicalScaleProductionAdapters({
    sourcePlan: source,
    targetPlan: target(),
    runner: {
      async run(request) {
        if (request.purpose === 'bootstrap-provision') {
          provisionCalls.push({ host: request.host, action: request.purpose });
          return { ok: true };
        }
        provisionCalls.push({
          host: request.host,
          action: request.purpose,
          payload: JSON.parse(Buffer.from(request.argv[3], 'base64').toString('utf8'))
        });
        return { ok: true, services: [], fingerprint: 'provisioned' };
      }
    },
    routePlan: { hash: 'a'.repeat(64), fileSha256: routeSha, bytes: routeBytes },
    gateway: {
      host: '43.242.194.89',
      service: 'xingyan-dual-cell-tls-live',
      healthPort: 5443
    },
    provisioning: {
      enabled: true,
      seedCellId: 'cell-a-43'
    }
  });
  await provisioningAdapters.prepareNode({ cellId: 'cell-c' });
  const provision = provisionCalls.find((row) => row.action === 'provision');
  assert.ok(provisionCalls.some((row) => row.action === 'bootstrap-provision'));
  assert.ok(provision);
  assert.strictEqual(provision.host, '192.0.2.40');
  assert.strictEqual(provision.payload.sourceHost, '43.242.194.89');
  assert.strictEqual(provision.payload.cellId, 'cell-c');
  assert.strictEqual(provision.payload.ports.length, 7);

  console.log('physical-scale-production-adapters: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
