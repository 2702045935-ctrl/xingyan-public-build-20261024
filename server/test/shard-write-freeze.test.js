'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { buildRoutePlan } = require('../lib/shard-route-plan');
const { switchWriteFreeze } = require('../lib/shard-write-freeze');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-write-freeze-'));
const ports = [7080, 7180, 7280, 7380, 7480, 7580, 7680];
const plan = buildRoutePlan({
  users: [],
  chats: [],
  shardCount: 7,
  ports,
  topologyId: 'write-freeze-test',
  baselineDate: '2026-11-17',
  createdAt: '2026-11-17T00:00:00Z'
});
const planFile = path.join(root, 'plan.json');
const secretFile = path.join(root, 'secret.key');
fs.writeFileSync(planFile, JSON.stringify(plan));
fs.writeFileSync(secretFile, 'test-secret');
const fileHash = crypto.createHash('sha256').update(fs.readFileSync(planFile)).digest('hex');
const states = new Map(ports.map((port) => [port, { frozen: false, epoch: 0 }]));
let failingPort = 0;
const originalFetch = global.fetch;

function response(status, payload) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => payload
  };
}

global.fetch = async (url, options) => {
  const parsed = new URL(url);
  const port = Number(parsed.port);
  const state = states.get(port);
  if (parsed.pathname === '/api/health') {
    return response(200, {
      ok: true,
      data: Object.assign({
        port,
        chatRoutePlanHash: plan.hash,
        chatRoutePlanFileHash: fileHash,
        writeFrozen: state.frozen,
        fenceEpoch: state.epoch
      })
    });
  }
  if (parsed.pathname === '/__shard/write-freeze' && options.method === 'POST') {
    if (options.headers['X-Shard-Relay'] !== 'test-secret') {
      return response(403, { ok: false, error: 'bad secret' });
    }
    const body = JSON.parse(options.body);
    if (port === failingPort && body.frozen === true) {
      return response(500, { ok: false, error: 'simulated failure' });
    }
    if (body.epoch !== state.epoch + 1) {
      return response(409, { ok: false, error: 'stale epoch' });
    }
    state.frozen = body.frozen;
    state.epoch = body.epoch;
    return response(200, {
      ok: true,
      data: { frozen: state.frozen, fenceEpoch: state.epoch }
    });
  }
  return response(404, { ok: false, error: 'not found' });
};

async function main() {
  let report = await switchWriteFreeze({
    ports,
    frozen: true,
    reason: 'test-cutover',
    secretFile,
    planFile
  });
  assert.strictEqual(report.fenceEpoch, 1);
  assert.ok(ports.every((port) => states.get(port).frozen === true
    && states.get(port).epoch === 1));

  report = await switchWriteFreeze({
    ports,
    frozen: false,
    secretFile,
    planFile
  });
  assert.strictEqual(report.fenceEpoch, 2);
  assert.ok(ports.every((port) => states.get(port).frozen === false
    && states.get(port).epoch === 2));

  failingPort = ports[4];
  await assert.rejects(() => switchWriteFreeze({
    ports,
    frozen: true,
    secretFile,
    planFile
  }), /simulated failure/);
  assert.ok(ports.every((port) => states.get(port).frozen === false));

  console.log('shard-write-freeze: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
}).finally(() => {
  global.fetch = originalFetch;
  fs.rmSync(root, { recursive: true, force: true });
});
