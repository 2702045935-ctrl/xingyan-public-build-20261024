'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');
const { spawn } = require('child_process');
const net = require('net');
const { patchServerSource } = require('../lib/shard-route-server-patch');
const { buildRoutePlan } = require('../lib/shard-route-plan');

async function main() {
const stable = execFileSync('git', ['show', 'bc09897:server/server.js'], {
  cwd: path.resolve(__dirname, '..', '..'),
  maxBuffer: 8 * 1024 * 1024
});
const expected = crypto.createHash('sha256').update(stable).digest('hex');
const result = patchServerSource(stable, { expectedSha256: expected });
assert.strictEqual(result.ok, true);
assert.deepStrictEqual(result.changes, [
  'requires',
  'route-runtime',
  'chat-owner-runtime',
  'client-routing',
  'health-fields',
  'tls-page',
  'admin-page-regex',
  'admin-entry-regex',
  'static-page-regex',
  'admin-path',
  'chat-action-endpoint'
]);
assert.ok(result.source.includes('SHARD_ROUTE_PLAN_FILE'));
assert.ok(result.source.includes('/__shard/chat-action'));
assert.ok(result.source.includes('chatOwnerPort(msg.chatId)'));
assert.ok(result.source.includes('chatRoutePlanFileHash'));
assert.throws(() => patchServerSource(stable, {
  expectedSha256: 'a'.repeat(64)
}), /stable server hash mismatch/);
assert.throws(() => patchServerSource(Buffer.from(result.source), {
  expectedSha256: result.outputSha256
}), /already contains/);

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-route-patch-'));
try {
  const file = path.join(root, 'server.js');
  fs.writeFileSync(file, result.source);
  const checked = spawnSync(process.execPath, ['--check', file], {
    encoding: 'utf8',
    windowsHide: true
  });
  assert.strictEqual(checked.status, 0, checked.stderr);

  const serverDir = path.resolve(__dirname, '..');
  const generated = path.join(serverDir, '.server-route-patch-' + process.pid + '.js');
  const dataDir = path.join(root, 'data');
  fs.mkdirSync(dataDir);
  const basePort = await freeBase(7);
  const ports = Array.from({ length: 7 }, (_, index) => basePort + index * 100);
  const plan = buildRoutePlan({
    users: [],
    chats: [],
    shardCount: 7,
    ports,
    topologyId: 'server-b-mainline-shards-7',
    baselineDate: '2026-11-16',
    createdAt: '2026-11-16T00:00:00Z'
  });
  const planFile = path.join(root, 'route-plan.json');
  fs.writeFileSync(planFile, JSON.stringify(plan));
  const planHash = crypto.createHash('sha256').update(fs.readFileSync(planFile)).digest('hex');
  fs.writeFileSync(generated, result.source);
  const logs = [];
  const child = spawn(process.execPath, [generated], {
    cwd: serverDir,
    env: Object.assign({}, process.env, {
      DATA_DIR: dataDir,
      PORT: String(basePort),
      HTTPS_PORT: String(await freePort()),
      TURN_PORT: String(await freePort()),
      SHARD_COUNT: '7',
      SHARD_ID: '0',
      SHARD_BASE_PORT: String(basePort),
      SHARD_ROUTE_PLAN_FILE: planFile,
      SHARD_ROUTE_PLAN_FILE_SHA256: planHash,
      SHARD_ROUTE_PLAN_ENFORCED: '0',
      CHRIS_LOCAL_ONLY: '1',
      DISABLE_STARTUP_BOT_BACKFILL: '1',
      AML_RUNTIME_ENABLED: '0'
    }),
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true
  });
  child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
  child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
  try {
    const health = await waitHealth('http://127.0.0.1:' + basePort, child, logs);
    assert.strictEqual(health.chatRoutePlanHash, plan.hash);
    assert.strictEqual(health.chatRoutePlanFileHash, planHash);
    assert.strictEqual(health.chatRouteTopologyId, plan.topologyId);
    assert.strictEqual(health.chatRoutePlanEnforced, false);
  } finally {
    if (child.exitCode === null) {
      child.kill();
      await new Promise((resolve) => child.once('exit', resolve));
    }
    fs.rmSync(generated, { force: true });
  }
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}

console.log('shard-route-server-patch: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});

async function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const port = server.address().port;
      server.close(() => resolve(port));
    });
  });
}

async function freeBase(count) {
  for (let base = 26000; base < 50000; base += 1) {
    const sockets = [];
    let ok = true;
    for (let index = 0; index < count; index += 1) {
      try {
        await new Promise((resolve, reject) => {
          const server = net.createServer();
          sockets.push(server);
          server.once('error', reject);
          server.listen(base + index * 100, '127.0.0.1', resolve);
        });
      } catch (_) {
        ok = false;
        break;
      }
    }
    await Promise.all(sockets.map((server) => new Promise((resolve) => server.close(resolve))));
    if (ok) return base;
  }
  throw new Error('no free shard port base');
}

async function waitHealth(base, child, logs) {
  for (let index = 0; index < 180; index += 1) {
    if (child.exitCode !== null) throw new Error(logs.join(''));
    try {
      const response = await fetch(base + '/api/health');
      if (response.ok) return (await response.json()).data;
    } catch (_) { /* wait */ }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('patched server start timeout');
}
