'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { buildRoutePlan } = require('../lib/shard-route-plan');
const { switchOwnerRouting } = require('../lib/shard-owner-switch');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-owner-switch-'));
const ports = [7080, 7180, 7280, 7380, 7480, 7580, 7680];
const plan = buildRoutePlan({
  users: [],
  chats: [],
  shardCount: 7,
  ports,
  topologyId: 'owner-switch-test',
  baselineDate: '2026-11-17',
  createdAt: '2026-11-17T00:00:00Z'
});
const planFile = path.join(root, 'plan.json');
const secretFile = path.join(root, 'secret.key');
fs.writeFileSync(planFile, JSON.stringify(plan));
fs.writeFileSync(secretFile, 'test-secret');
const fileHash = crypto.createHash('sha256').update(fs.readFileSync(planFile)).digest('hex');
const states = new Map(ports.map((port) => [port, false]));
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
  if (parsed.pathname === '/api/health') {
    return response(200, {
      ok: true,
      data: {
        port,
        chatRoutePlanHash: plan.hash,
        chatRoutePlanFileHash: fileHash,
        chatRoutePlanEnforced: states.get(port)
      }
    });
  }
  if (parsed.pathname === '/__shard/owner-routing' && options.method === 'POST') {
    if ((options.headers['X-Shard-Relay'] || options.headers['x-shard-relay']) !== 'test-secret') {
      return response(403, { ok: false, error: 'bad secret' });
    }
    const body = JSON.parse(options.body);
    if (port === failingPort && body.enabled === true) {
      return response(500, { ok: false, error: 'simulated failure' });
    }
    states.set(port, body.enabled === true);
    return response(200, {
      ok: true,
      data: { enabled: states.get(port), planHash: plan.hash, fileSha256: fileHash }
    });
  }
  return response(404, { ok: false, error: 'not found' });
};

async function main() {
  let report = await switchOwnerRouting({
    ports,
    enable: true,
    secretFile,
    planFile
  });
  assert.strictEqual(report.ok, true);
  assert.ok(ports.every((port) => states.get(port) === true));

  report = await switchOwnerRouting({
    ports,
    enable: false,
    secretFile,
    planFile
  });
  assert.strictEqual(report.ok, true);
  assert.ok(ports.every((port) => states.get(port) === false));

  failingPort = ports[4];
  await assert.rejects(() => switchOwnerRouting({
    ports,
    enable: true,
    secretFile,
    planFile
  }), /simulated failure/);
  assert.ok(ports.every((port) => states.get(port) === false));

  console.log('shard-owner-switch: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
}).finally(() => {
  global.fetch = originalFetch;
  fs.rmSync(root, { recursive: true, force: true });
});
