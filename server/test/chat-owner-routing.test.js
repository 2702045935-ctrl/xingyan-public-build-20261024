'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn, spawnSync } = require('child_process');
const { buildRoutePlan, resolveRoute } = require('../lib/shard-route-plan');
const { openMessage } = require('../lib/shard-data-inventory');
const { SecurityVault } = require('../lib/security-vault');

const SERVER_DIR = path.resolve(__dirname, '..');
const PASSWORD = 'test123456';

async function freeBase(count) {
  for (let base = 26000; base < 50000; base += 1) {
    const sockets = [];
    let ok = true;
    for (let index = 0; index < count; index += 1) {
      const port = base + index * 100;
      try {
        await new Promise((resolve, reject) => {
          const server = net.createServer();
          sockets.push(server);
          server.once('error', reject);
          server.listen(port, '127.0.0.1', resolve);
        });
      } catch (_) {
        ok = false;
        break;
      }
    }
    await Promise.all(sockets.map((server) => new Promise((resolve) => server.close(resolve))));
    if (ok) return base;
  }
  throw new Error('no free shard port pair');
}

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

function makeUser(id, username) {
  const salt = crypto.randomBytes(16).toString('hex');
  return {
    id,
    username,
    nickname: username,
    avatar: '',
    bio: '',
    phone: '',
    gender: 'secret',
    balance: 0,
    transferLimit: 20000,
    salt,
    passwordHash: crypto.scryptSync(PASSWORD, salt, 64).toString('hex'),
    createdAt: new Date().toISOString(),
    tokenVersion: 0,
    phoneSession: 0
  };
}

async function waitHealth(base, child, logs) {
  for (let index = 0; index < 180; index += 1) {
    if (child.exitCode !== null) throw new Error(logs.join(''));
    try {
      const response = await fetch(base + '/api/health');
      if (response.ok) return;
    } catch (_) { /* wait */ }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('server start timeout');
}

async function startShard(
  dataDir,
  port,
  basePort,
  shardId,
  shardCount,
  routePlanFile,
  routePlanFileHash,
  routePlanEnforced,
  runtimeManifestFile,
  topologyFile
) {
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  const child = spawn(process.execPath, ['server.js'], {
    cwd: SERVER_DIR,
    env: Object.assign({}, process.env, {
      DATA_DIR: dataDir,
      PORT: String(port),
      HTTPS_PORT: String(await freePort()),
      TURN_PORT: String(await freePort()),
      SHARD_COUNT: String(shardCount),
      SHARD_ID: String(shardId),
      SHARD_BASE_PORT: String(basePort),
      SHARD_ROUTE_PLAN_FILE: routePlanFile,
      SHARD_ROUTE_PLAN_FILE_SHA256: routePlanFileHash,
      SHARD_ROUTE_PLAN_ENFORCED: routePlanEnforced ? '1' : '0',
      SHARD_RUNTIME_MANIFEST: runtimeManifestFile,
      SHARD_TOPOLOGY_FILE: topologyFile,
      CHRIS_LOCAL_ONLY: '1',
      DISABLE_STARTUP_BOT_BACKFILL: '1',
      AML_RUNTIME_ENABLED: '0'
    }),
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true
  });
  child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
  child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
  await waitHealth(base, child, logs);
  return { base, child, logs };
}

async function login(base, username) {
  const response = await fetch(base + '/api/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-device-kind': 'phone' },
    body: JSON.stringify({ username, password: PASSWORD })
  });
  const payload = await response.json();
  assert.strictEqual(response.status, 200, JSON.stringify(payload));
  const raw = response.headers.getSetCookie
    ? response.headers.getSetCookie()[0]
    : response.headers.get('set-cookie') || '';
  return { cookie: raw.split(';')[0], user: payload.data.user };
}

function connect(base, cookie) {
  const token = cookie.slice(cookie.indexOf('=') + 1);
  const socket = new WebSocket(base.replace(/^http/, 'ws') + '/?token=' + encodeURIComponent(token));
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('ws timeout')), 6000);
    socket.addEventListener('error', () => reject(new Error('ws failed')));
    socket.addEventListener('message', (event) => {
      try {
        if (JSON.parse(String(event.data || '')).type === 'ready') {
          clearTimeout(timer);
          resolve(socket);
        }
      } catch (_) { /* ignore */ }
    });
  });
}

async function waitFor(condition, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (condition()) return;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error('wait timeout');
}

async function stop(child) {
  if (!child || child.exitCode !== null) return;
  child.kill();
  await new Promise((resolve) => child.once('exit', resolve));
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-chat-owner-'));
  const shardCount = 7;
  const basePort = await freeBase(shardCount);
  const servers = [];
  let aliceSocket;
  let bobSocket;
  try {
    const alice = makeUser('u_chat_owner_alice', 'chat_owner_alice');
    const bob = makeUser('u_chat_owner_bob', 'chat_owner_bob');
    const chatId = 'c_chat_owner_routing';
    const extraChatIds = Array.from({ length: 4 }, (_, index) => 'c_owner_multichat_' + index);
    const allChatIds = [chatId, ...extraChatIds];
    const ports = Array.from(
      { length: shardCount },
      (_, index) => basePort + index * 100
    );
    const routePlan = buildRoutePlan({
      users: [alice, bob],
      chats: allChatIds.map((id) => ({ id })),
      shardCount,
      ports,
      topologyId: 'chat-owner-routing-7-test',
      baselineDate: '2026-11-16',
      createdAt: '2026-11-16T00:00:00Z'
    });
    const routePlanFile = path.join(dataDir, 'chat-route-plan.json');
    fs.writeFileSync(routePlanFile, JSON.stringify(routePlan, null, 2));
    const routePlanFileHash = crypto.createHash('sha256')
      .update(fs.readFileSync(routePlanFile))
      .digest('hex');
    const topologyFile = path.join(dataDir, 'test-topologies.json');
    fs.writeFileSync(topologyFile, JSON.stringify({
      version: 1,
      topologies: {
        [routePlan.topologyId]: {
          shardCount,
          ports
        }
      }
    }, null, 2));
    const runtimeManifestFile = path.join(dataDir, 'runtime-manifest.json');
    fs.writeFileSync(runtimeManifestFile, JSON.stringify({
      version: 1,
      environment: 'test',
      topologyId: routePlan.topologyId,
      host: '127.0.0.1',
      entryHost: '127.0.0.1',
      programDir: '/tmp/chat-owner-routing-app',
      dataDir: '/tmp/chat-owner-routing-data',
      serviceTemplate: 'chat-owner-routing-shard@{id}.service',
      shardCount,
      backendBasePort: basePort,
      entryBasePort: basePort + 1000,
      portStep: 100,
      frozenDate: '2026-11-16',
      frozenCodeHash: 'b'.repeat(64)
    }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({ users: [alice, bob] }));
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({ sliderLogin: 0 }));
    fs.writeFileSync(path.join(dataDir, 'friendships.json'), JSON.stringify({
      friendships: [{
        id: 'f_chat_owner',
        fromId: alice.id,
        toId: bob.id,
        status: 'accepted',
        createdAt: new Date().toISOString()
      }]
    }));
    fs.writeFileSync(path.join(dataDir, 'chats.json'), JSON.stringify({
      chats: allChatIds.map((id) => ({
        id,
        type: 'direct',
        memberIds: [alice.id, bob.id],
        seq: 0,
        createdAt: new Date().toISOString()
      }))
    }));
    for (let shard = 0; shard < shardCount; shard += 1) {
      servers.push(await startShard(
        dataDir,
        basePort + shard * 100,
        basePort,
        shard,
        shardCount,
        routePlanFile,
        routePlanFileHash,
        false,
        runtimeManifestFile,
        topologyFile
      ));
    }
    const dormantHealth = await Promise.all(servers.map(async (server) => {
      const response = await fetch(server.base + '/api/health');
      return (await response.json()).data;
    }));
    for (const row of dormantHealth) {
      assert.strictEqual(row.chatRoutePlanHash, routePlan.hash);
      assert.strictEqual(row.chatRoutePlanFileHash, routePlanFileHash);
      assert.strictEqual(row.chatRouteTopologyId, routePlan.topologyId);
      assert.strictEqual(row.chatRoutePlanEnforced, false);
    }
    const auditTool = path.join(SERVER_DIR, 'tools', 'shard-runtime-audit.js');
    const dormantAudit = spawnSync(process.execPath, [
      auditTool,
      '--manifest=' + runtimeManifestFile,
      '--topology=' + topologyFile,
      '--route-plan=' + routePlanFile,
      '--route-plan-file-sha256=' + routePlanFileHash,
      '--require-route-dormant',
      '--no-systemd',
      '--no-code'
    ], { encoding: 'utf8', windowsHide: true });
    assert.strictEqual(dormantAudit.status, 0,
      dormantAudit.stderr || dormantAudit.stdout);
    const dormantAuditReport = JSON.parse(dormantAudit.stdout);
    assert.strictEqual(dormantAuditReport.ok, true);
    assert.strictEqual(dormantAuditReport.routePlan.requiredMode, 'dormant');
    const wrongModeAudit = spawnSync(process.execPath, [
      auditTool,
      '--manifest=' + runtimeManifestFile,
      '--topology=' + topologyFile,
      '--route-plan=' + routePlanFile,
      '--route-plan-file-sha256=' + routePlanFileHash,
      '--require-route-enforced',
      '--no-systemd',
      '--no-code'
    ], { encoding: 'utf8', windowsHide: true });
    assert.strictEqual(wrongModeAudit.status, 1);
    const wrongModeReport = JSON.parse(wrongModeAudit.stdout);
    assert.strictEqual(wrongModeReport.ok, false);
    assert.ok(wrongModeReport.shards.every((row) =>
      row.failures.includes('chat-route-plan-not-enforced')
    ));
    for (const server of servers) await stop(server.child);
    servers.length = 0;
    for (let shard = 0; shard < shardCount; shard += 1) {
      servers.push(await startShard(
        dataDir,
        basePort + shard * 100,
        basePort,
        shard,
        shardCount,
        routePlanFile,
        routePlanFileHash,
        true,
        runtimeManifestFile,
        topologyFile
      ));
    }
    const aliceUserShard = resolveRoute(routePlan, 'user', alice.id);
    const bobUserShard = resolveRoute(routePlan, 'user', bob.id);
    const aliceLogin = await login(servers[aliceUserShard].base, alice.username);
    const bobLogin = await login(servers[bobUserShard].base, bob.username);
    aliceSocket = await connect(servers[aliceUserShard].base, aliceLogin.cookie);
    bobSocket = await connect(servers[bobUserShard].base, bobLogin.cookie);
    for (let index = 0; index < 20; index += 1) {
      aliceSocket.send(JSON.stringify({
        type: 'send', chatId, kind: 'text',
        content: 'alice-' + index, clientId: 'alice-client-' + index
      }));
      bobSocket.send(JSON.stringify({
        type: 'send', chatId, kind: 'text',
        content: 'bob-' + index, clientId: 'bob-client-' + index
      }));
    }
    const messageFile = path.join(dataDir, 'messages', chatId + '.jsonl');
    await waitFor(() => fs.existsSync(messageFile)
      && fs.readFileSync(messageFile, 'utf8').split('\n').filter(Boolean).length >= 40, 10000);
    const secret = fs.readFileSync(path.join(dataDir, 'secret.key'), 'utf8').trim();
    const vault = fs.existsSync(path.join(dataDir, 'keyring.json'))
      ? new SecurityVault({ dataDir, rootMaterial: secret })
      : null;
    const rows = fs.readFileSync(messageFile, 'utf8').split('\n').filter(Boolean)
      .map((line) => openMessage(secret, chatId, line, vault));
    assert.strictEqual(rows.length, 40);
    assert.strictEqual(new Set(rows.map((row) => row.id)).size, 40);
    assert.strictEqual(new Set(rows.map((row) => row.seq)).size, 40);
    assert.deepStrictEqual(
      rows.map((row) => row.seq).sort((left, right) => left - right),
      Array.from({ length: 40 }, (_, index) => index + 1)
    );
    const readChatRows = async (id, expected) => {
      const file = path.join(dataDir, 'messages', id + '.jsonl');
      await waitFor(() => fs.existsSync(file)
        && fs.readFileSync(file, 'utf8').split('\n').filter(Boolean).length >= expected, 10000);
      return fs.readFileSync(file, 'utf8').split('\n').filter(Boolean)
        .map((line) => openMessage(secret, id, line, vault));
    };
    for (let chatIndex = 0; chatIndex < extraChatIds.length; chatIndex += 1) {
      const id = extraChatIds[chatIndex];
      for (let index = 0; index < 10; index += 1) {
        aliceSocket.send(JSON.stringify({
          type: 'send', chatId: id, kind: 'text',
          content: 'multi-alice-' + chatIndex + '-' + index,
          clientId: 'multi-alice-' + chatIndex + '-' + index
        }));
        bobSocket.send(JSON.stringify({
          type: 'send', chatId: id, kind: 'text',
          content: 'multi-bob-' + chatIndex + '-' + index,
          clientId: 'multi-bob-' + chatIndex + '-' + index
        }));
      }
    }
    for (const id of extraChatIds) {
      const chatRows = await readChatRows(id, 20);
      assert.strictEqual(chatRows.length, 20);
      assert.strictEqual(new Set(chatRows.map((row) => row.seq)).size, 20);
      assert.deepStrictEqual(
        chatRows.map((row) => row.seq).sort((left, right) => left - right),
        Array.from({ length: 20 }, (_, index) => index + 1)
      );
    }
    const ownerIndex = resolveRoute(routePlan, 'chat', chatId);
    assert.notStrictEqual(ownerIndex, aliceUserShard);
    assert.notStrictEqual(ownerIndex, bobUserShard);
    await stop(servers[ownerIndex].child);
    servers[ownerIndex] = await startShard(
      dataDir,
      basePort + ownerIndex * 100,
      basePort,
      ownerIndex,
      shardCount,
      routePlanFile,
      routePlanFileHash,
      true,
      runtimeManifestFile,
      topologyFile
    );
    for (let index = 20; index < 30; index += 1) {
      aliceSocket.send(JSON.stringify({
        type: 'send', chatId, kind: 'text',
        content: 'alice-post-restart-' + index,
        clientId: 'alice-post-restart-' + index
      }));
      bobSocket.send(JSON.stringify({
        type: 'send', chatId, kind: 'text',
        content: 'bob-post-restart-' + index,
        clientId: 'bob-post-restart-' + index
      }));
    }
    const finalRows = await readChatRows(chatId, 60);
    assert.strictEqual(finalRows.length, 60);
    assert.strictEqual(new Set(finalRows.map((row) => row.id)).size, 60);
    assert.strictEqual(new Set(finalRows.map((row) => row.seq)).size, 60);
    assert.deepStrictEqual(
      finalRows.map((row) => row.seq).sort((left, right) => left - right),
      Array.from({ length: 60 }, (_, index) => index + 1)
    );
    const healthRows = await Promise.all(servers.map(async (server) => {
      const response = await fetch(server.base + '/api/health');
      return (await response.json()).data;
    }));
    const forwarded = healthRows.reduce(
      (sum, row) => sum + Number(row.chatOwnerForwards || 0),
      0
    );
    for (const row of healthRows) {
      assert.strictEqual(row.chatRoutePlanHash, routePlan.hash);
      assert.strictEqual(row.chatRoutePlanFileHash, routePlanFileHash);
      assert.strictEqual(row.chatRouteTopologyId, routePlan.topologyId);
      assert.strictEqual(row.chatRoutePlanEnforced, true);
    }
    const enforcedAudit = spawnSync(process.execPath, [
      auditTool,
      '--manifest=' + runtimeManifestFile,
      '--topology=' + topologyFile,
      '--route-plan=' + routePlanFile,
      '--route-plan-file-sha256=' + routePlanFileHash,
      '--require-route-enforced',
      '--no-systemd',
      '--no-code'
    ], { encoding: 'utf8', windowsHide: true });
    assert.strictEqual(enforcedAudit.status, 0,
      enforcedAudit.stderr || enforcedAudit.stdout);
    const enforcedAuditReport = JSON.parse(enforcedAudit.stdout);
    assert.strictEqual(enforcedAuditReport.ok, true);
    assert.strictEqual(enforcedAuditReport.routePlan.requiredMode, 'enforced');
    assert.ok(forwarded >= 1);
    const summary = {
      ok: true,
      shardCount,
      routePlanHash: routePlan.hash,
      routePlanFileHash,
      routeTopologyId: routePlan.topologyId,
      dormantInstancesChecked: dormantHealth.length,
      dormantAudit: dormantAuditReport.ok,
      modeMismatchRejected: wrongModeReport.ok === false,
      enforcedAudit: enforcedAuditReport.ok,
      chatId,
      chatOwnerShard: ownerIndex,
      aliceUserShard,
      bobUserShard,
      multiChatCount: 1 + extraChatIds.length,
      ownerRestarted: true,
      messagesPerSender: 30,
      finalMessages: finalRows.length,
      uniqueSequences: new Set(finalRows.map((row) => row.seq)).size,
      sequenceMin: Math.min(...finalRows.map((row) => row.seq)),
      sequenceMax: Math.max(...finalRows.map((row) => row.seq)),
      chatOwnerForwards: forwarded
    };
    if (process.env.CHAT_OWNER_REPORT) {
      fs.writeFileSync(process.env.CHAT_OWNER_REPORT, JSON.stringify(summary, null, 2));
    }
    console.log('chat-owner-routing: passed ' + JSON.stringify(summary));
  } finally {
    aliceSocket?.close();
    bobSocket?.close();
    for (const server of servers) await stop(server.child);
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
