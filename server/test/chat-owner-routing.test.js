'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { routeShard } = require('../lib/shard-route-plan');
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

async function startShard(dataDir, port, basePort, shardId, shardCount) {
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
      chats: [{
        id: chatId,
        type: 'direct',
        memberIds: [alice.id, bob.id],
        seq: 0,
        createdAt: new Date().toISOString()
      }]
    }));
    for (let shard = 0; shard < shardCount; shard += 1) {
      servers.push(await startShard(
        dataDir,
        basePort + shard * 100,
        basePort,
        shard,
        shardCount
      ));
    }
    const aliceUserShard = routeShard('u:' + alice.id, shardCount);
    const bobUserShard = routeShard('u:' + bob.id, shardCount);
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
    const healthRows = await Promise.all(servers.map(async (server) => {
      const response = await fetch(server.base + '/api/health');
      return (await response.json()).data;
    }));
    assert.ok(healthRows.reduce((sum, row) => sum + Number(row.chatOwnerForwards || 0), 0) >= 1);
    console.log('chat-owner-routing: passed');
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
