'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const {
  FROZEN_TARGET,
  READY_CHECKLIST,
  ShardMaintenanceStore
} = require('../lib/shard-maintenance');

const SERVER_DIR = path.resolve(__dirname, '..');
const ADMIN_PASSWORD = 'maintenance-api-admin';

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

async function waitHealth(base, child, logs) {
  for (let index = 0; index < 200; index += 1) {
    if (child.exitCode !== null) throw new Error(logs.join(''));
    try {
      const response = await fetch(base + '/api/health');
      if (response.ok) return;
    } catch (_) { /* wait */ }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('server start timeout');
}

async function call(base, cookie, method, pathname, body) {
  const headers = {};
  if (cookie) headers.Cookie = cookie;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const response = await fetch(base + pathname, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const payload = await response.json();
  const rawCookie = response.headers.getSetCookie
    ? response.headers.getSetCookie()[0]
    : response.headers.get('set-cookie') || '';
  return {
    status: response.status,
    payload,
    cookie: rawCookie ? rawCookie.split(';')[0] : ''
  };
}

async function stop(child) {
  if (!child || child.exitCode !== null) return;
  child.kill();
  await new Promise((resolve) => child.once('exit', resolve));
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-maintenance-api-'));
  const fleetFile = path.join(dataDir, 'current-fleet.json');
  const port = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  const child = spawn(process.execPath, ['server.js'], {
    cwd: SERVER_DIR,
    env: Object.assign({}, process.env, {
      DATA_DIR: dataDir,
      PORT: String(port),
      HTTPS_PORT: String(await freePort()),
      TURN_PORT: String(await freePort()),
      CHRIS_LOCAL_ONLY: '1',
      DISABLE_STARTUP_BOT_BACKFILL: '1',
      AML_RUNTIME_ENABLED: '0',
      PHYSICAL_FLEET_PLAN: fleetFile,
      ADMIN_PASSWORD
    }),
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true
  });
  child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
  child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
  try {
    await waitHealth(base, child, logs);
    let response = await call(base, '', 'POST', '/api/ops/login', {
      username: 'admin',
      password: ADMIN_PASSWORD
    });
    assert.strictEqual(response.status, 200, JSON.stringify(response.payload));
    const cookie = response.cookie;

    response = await call(base, cookie, 'GET', '/api/ops/fleet');
    assert.strictEqual(response.status, 200, JSON.stringify(response.payload));
    const fleetPlan = response.payload.data.plan;
    assert.ok(Array.isArray(fleetPlan.cells) && fleetPlan.cells.length >= 2);

    response = await call(base, cookie, 'PUT', '/api/ops/fleet', {
      plan: fleetPlan
    });
    assert.strictEqual(response.status, 428, JSON.stringify(response.payload));
    response = await call(base, cookie, 'PUT', '/api/ops/fleet', {
      plan: fleetPlan,
      confirmPassword: ADMIN_PASSWORD
    });
    assert.strictEqual(response.status, 200, JSON.stringify(response.payload));
    assert.ok(fs.existsSync(fleetFile));

    response = await call(base, cookie, 'GET', '/api/ops/shardmaintenance');
    assert.strictEqual(response.status, 200, JSON.stringify(response.payload));
    assert.strictEqual(response.payload.data.frozen.routePlanHash,
      FROZEN_TARGET.routePlanHash);
    assert.deepStrictEqual(response.payload.data.checklist, READY_CHECKLIST);

    response = await call(base, cookie, 'POST', '/api/ops/shardmaintenance/capacity', {});
    assert.strictEqual(response.status, 200, JSON.stringify(response.payload));
    assert.strictEqual(response.payload.data.report.readOnly, true);
    assert.match(response.payload.data.report.audit.fingerprint, /^[a-f0-9]{64}$/);

    const candidateCodeSha256 = 'a'.repeat(64);
    response = await call(base, cookie, 'POST', '/api/ops/shardmaintenance/create', {
      phase: 'dormant',
      candidateCommit: 'd80705dc9b7b77149fa2575ec0d450d63171693a',
      candidateCodeSha256,
      artifactPath: '/opt/xingyan-mainline/releases/candidate',
      backupRoot: '/opt/xingyan-mainline/backups/candidate'
    });
    assert.strictEqual(response.status, 200, JSON.stringify(response.payload));
    const rolloutId = response.payload.data.rollout.id;
    assert.strictEqual(response.payload.data.rollout.status, 'draft');

    const checklist = Object.fromEntries(READY_CHECKLIST.map((key) => [key, true]));
    const capacityReport = {
      readOnly: true,
      ok: true,
      input: {
        collectedAt: new Date().toISOString(),
        shards: FROZEN_TARGET.shards.map((shard) => ({
          id: shard.id,
          pid: 5000 + shard.id,
          rssBytes: 300 * 1024 * 1024,
          fdCount: 900
        }))
      },
      audit: {
        ok: true,
        fingerprint: 'e'.repeat(64),
        failures: []
      },
      failures: []
    };
    response = await call(base, cookie, 'POST', '/api/ops/shardmaintenance/ready', {
      id: rolloutId,
      checklist,
      confirmation: '只逐片发布',
      capacityReport
    });
    assert.strictEqual(response.status, 428, JSON.stringify(response.payload));

    response = await call(base, cookie, 'POST', '/api/ops/shardmaintenance/ready', {
      id: rolloutId,
      checklist,
      confirmation: '只逐片发布',
      capacityReport,
      confirmPassword: ADMIN_PASSWORD
    });
    assert.strictEqual(response.status, 200, JSON.stringify(response.payload));
    assert.strictEqual(response.payload.data.rollout.status, 'ready');

    response = await call(base, cookie, 'POST', '/api/ops/shardmaintenance/deploy', {
      id: rolloutId,
      confirmPassword: ADMIN_PASSWORD
    });
    assert.strictEqual(response.status, 200, JSON.stringify(response.payload));
    assert.strictEqual(response.payload.data.rollout.currentShard, 0);
    assert.strictEqual(response.payload.data.rollout.status, 'awaiting_execution');

    const executorStore = new ShardMaintenanceStore(
      path.join(dataDir, 'shard-maintenance.json')
    );
    const executorActor = {
      id: 'executor_test',
      username: 'shard-executor',
      name: '测试执行器',
      role: 'automation'
    };
    executorStore.transition(rolloutId, 'claim', { shardId: 0 }, executorActor);
    executorStore.transition(rolloutId, 'complete', {
      shardId: 0,
      afterCodeSha256: candidateCodeSha256,
      afterPid: 43210,
      systemdActive: true
    }, executorActor);

    const evidence = {
      shardId: 0,
      service: FROZEN_TARGET.shards[0].service,
      backendPort: FROZEN_TARGET.shards[0].backendPort,
      runtimeManifestHash: FROZEN_TARGET.runtimeManifestHash,
      runtimeTopologyId: FROZEN_TARGET.topologyId,
      chatRoutePlanHash: FROZEN_TARGET.routePlanHash,
      chatRoutePlanFileHash: FROZEN_TARGET.routePlanFileSha256,
      chatRoutePlanEnforced: false,
      activeCalls: 0,
      ringingCalls: 0
    };
    response = await call(base, cookie, 'POST', '/api/ops/shardmaintenance/health', {
      id: rolloutId,
      shardId: 0,
      ok: true,
      evidence
    });
    assert.strictEqual(response.status, 200, JSON.stringify(response.payload));
    assert.strictEqual(response.payload.data.rollout.status, 'awaiting_approval');

    response = await call(base, cookie, 'POST', '/api/ops/shardmaintenance/approve', {
      id: rolloutId,
      confirmation: '确认第1片健康',
      confirmPassword: ADMIN_PASSWORD
    });
    assert.strictEqual(response.status, 422, JSON.stringify(response.payload));

    response = await call(base, cookie, 'POST', '/api/ops/shardmaintenance/approve', {
      id: rolloutId,
      confirmation: '确认第0片健康',
      confirmPassword: ADMIN_PASSWORD
    });
    assert.strictEqual(response.status, 200, JSON.stringify(response.payload));
    assert.strictEqual(response.payload.data.rollout.status, 'ready');
    assert.strictEqual(response.payload.data.rollout.currentShard, 1);
    assert.strictEqual(response.payload.data.rollout.shards[0].status, 'healthy');
    assert.strictEqual(response.payload.data.rollout.shards[1].status, 'pending');
    assert.strictEqual(response.payload.data.rollout.shards[2].status, 'pending');

    response = await call(base, cookie, 'GET', '/api/ops/shardmaintenance');
    assert.strictEqual(response.status, 200, JSON.stringify(response.payload));
    assert.strictEqual(response.payload.data.rollouts.length, 1);
    assert.ok(fs.existsSync(path.join(dataDir, 'shard-maintenance.json')));
    assert.ok(fs.readFileSync(path.join(dataDir, 'audit.log'), 'utf8')
      .includes('生成当前分片执行请求'));

    console.log('shard-maintenance-api: passed ' + JSON.stringify({
      shard0: 'healthy',
      currentShard: 1,
      subsequentShards: 'pending'
    }));
  } finally {
    await stop(child);
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
