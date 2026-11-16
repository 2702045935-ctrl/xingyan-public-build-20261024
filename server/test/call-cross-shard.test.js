'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const SERVER_DIR = path.resolve(__dirname, '..');
const PASSWORD = 'test123456';

function listenOnce(port) {
  return new Promise((resolve, reject) => {
    const socket = net.createServer();
    socket.once('error', reject);
    socket.listen(port, '127.0.0.1', () => {
      socket.close(() => resolve(port));
    });
  });
}

async function freeShardBase() {
  for (let base = 24000; base < 50000; base += 1) {
    try {
      await listenOnce(base);
      await listenOnce(base + 100);
      return base;
    } catch (_) {
      // 继续找一对间隔 100 的空闲端口，和生产分片端口规则一致。
    }
  }
  throw new Error('找不到可用的跨分片测试端口');
}

function freePort() {
  return new Promise((resolve, reject) => {
    const socket = net.createServer();
    socket.once('error', reject);
    socket.listen(0, '127.0.0.1', () => {
      const port = socket.address().port;
      socket.close(() => resolve(port));
    });
  });
}

function user(id, username, nickname) {
  const salt = crypto.randomBytes(16).toString('hex');
  return {
    id,
    username,
    nickname,
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

async function waitForHealth(base, child, logs) {
  for (let index = 0; index < 180; index += 1) {
    if (child.exitCode !== null) {
      throw new Error('测试分片提前退出：\n' + logs.join(''));
    }
    try {
      if ((await fetch(base + '/api/health')).ok) return;
    } catch (_) {
      // 等待分片启动。
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('测试分片启动超时：\n' + logs.join(''));
}

async function startShard(dataDir, port, shardId, shardBase) {
  const base = 'http://127.0.0.1:' + port;
  const turnPort = await freePort();
  const httpsPort = await freePort();
  const logs = [];
  const child = spawn(process.execPath, ['server.js'], {
    cwd: SERVER_DIR,
    env: Object.assign({}, process.env, {
      DATA_DIR: dataDir,
      PORT: String(port),
      HTTPS_PORT: String(httpsPort),
      TURN_PORT: String(turnPort),
      SHARD_COUNT: '2',
      SHARD_ID: String(shardId),
      SHARD_BASE_PORT: String(shardBase),
      CALL_SIGNAL_PORT: String(shardBase),
      CHRIS_LOCAL_ONLY: '1',
      AML_RUNTIME_ENABLED: '0',
      DISABLE_STARTUP_BOT_BACKFILL: '1'
    }),
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true
  });
  child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
  child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
  await waitForHealth(base, child, logs);
  return { base, child, logs };
}

async function request(base, cookie, method, route, body) {
  const headers = { 'x-device-kind': 'phone' };
  if (cookie) headers.Cookie = cookie;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const response = await fetch(base + route, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await response.text();
  const envelope = text ? JSON.parse(text) : {};
  return {
    response,
    data: envelope.data === undefined ? envelope : envelope.data
  };
}

async function login(base, username) {
  const result = await request(base, '', 'POST', '/api/login', {
    username,
    password: PASSWORD
  });
  assert.equal(result.response.status, 200, JSON.stringify(result.data));
  const raw = result.response.headers.getSetCookie
    ? result.response.headers.getSetCookie()[0]
    : result.response.headers.get('set-cookie') || '';
  return { cookie: raw.split(';')[0], user: result.data.user };
}

function connect(base, cookie) {
  const pair = cookie.split(';').map((part) => part.trim())
    .find((part) => part.includes('=')) || '';
  const token = pair.slice(pair.indexOf('=') + 1);
  const events = [];
  const socket = new WebSocket(
    base.replace(/^http/, 'ws') + '/?token=' + encodeURIComponent(token)
  );
  socket.addEventListener('message', (event) => {
    try {
      events.push(JSON.parse(String(event.data || '')));
    } catch (_) {
      // 忽略无法解析的测试事件。
    }
  });
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('WebSocket 连接超时')), 6000);
    socket.addEventListener('error', () => {
      clearTimeout(timer);
      reject(new Error('WebSocket 连接失败'));
    });
    socket.addEventListener('message', (event) => {
      try {
        if (JSON.parse(String(event.data || '')).type === 'ready') {
          clearTimeout(timer);
          resolve({ socket, events });
        }
      } catch (_) {
        // 忽略无法解析的测试事件。
      }
    });
  });
}

async function waitEvent(events, predicate, description) {
  const deadline = Date.now() + 8000;
  while (Date.now() < deadline) {
    const found = events.find(predicate);
    if (found) return found;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error('等待跨片' + description + '超时：' + JSON.stringify(events.slice(-30)));
}

async function stopChild(child) {
  if (!child || child.exitCode !== null) return;
  const exited = new Promise((resolve) => child.once('exit', resolve));
  child.kill();
  await Promise.race([
    exited,
    new Promise((resolve) => setTimeout(resolve, 3000))
  ]);
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-call-cross-shard-'));
  const shardBase = await freeShardBase();
  let shardA;
  let shardB;
  let aliceSocket;
  let bobSocket;
  let charlieSocket;

  try {
    const aliceUser = user('u_cross_shard_alice', 'cross_shard_alice', 'Alice');
    const bobUser = user('u_cross_shard_bob', 'cross_shard_bob', 'Bob');
    const charlieUser = user('u_cross_shard_charlie', 'cross_shard_charlie', 'Charlie');
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [aliceUser, bobUser, charlieUser]
    }));
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({ sliderLogin: 0 }));
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }));
    fs.writeFileSync(path.join(dataDir, 'friendships.json'), JSON.stringify({
      friendships: [
        {
          id: 'friend-cross-shard',
          fromId: aliceUser.id,
          toId: bobUser.id,
          status: 'accepted',
          createdAt: new Date().toISOString()
        },
        {
          id: 'friend-cross-shard-busy',
          fromId: aliceUser.id,
          toId: charlieUser.id,
          status: 'accepted',
          createdAt: new Date().toISOString()
        }
      ]
    }));
    fs.writeFileSync(path.join(dataDir, 'chats.json'), JSON.stringify({
      chats: [{
        id: 'c_cross_shard',
        type: 'direct',
        memberIds: [aliceUser.id, bobUser.id],
        seq: 0,
        createdAt: new Date().toISOString()
      }]
    }));

    shardA = await startShard(dataDir, shardBase, 0, shardBase);
    shardB = await startShard(dataDir, shardBase + 100, 1, shardBase);
    const healthA = await request(shardA.base, '', 'GET', '/api/health');
    const healthB = await request(shardB.base, '', 'GET', '/api/health');
    assert.equal(healthA.data.role, 'call-signal');
    assert.equal(healthB.data.role, 'chat-shard');
    assert.equal(healthA.data.callSignalPort, shardBase);
    assert.equal(healthB.data.callSignalPort, shardBase);
    const alice = await login(shardA.base, aliceUser.username);
    const bob = await login(shardB.base, bobUser.username);
    aliceSocket = await connect(shardA.base, alice.cookie);

    const callId = 'call-cross-shard-' + Date.now();
    aliceSocket.socket.send(JSON.stringify({
      type: 'call',
      action: 'invite',
      callId,
      toUserId: bob.user.id,
      media: 'audio'
    }));
    const ringing = await waitEvent(aliceSocket.events, (event) =>
      event.type === 'call' && event.action === 'ringing' && event.callId === callId,
    '主叫响铃');
    assert.equal(ringing.offline, true);

    await new Promise((resolve) => setTimeout(resolve, 250));
    const pending = await request(shardB.base, bob.cookie, 'GET', '/api/call/pending');
    assert.equal(pending.response.status, 200, JSON.stringify(pending.data));
    assert.equal(pending.data.call.callId, callId);

    bobSocket = await connect(shardB.base, bob.cookie);
    const ready = await waitEvent(bobSocket.events, (event) => event.type === 'ready',
      '被叫重连');
    assert.equal(ready.callActive, true);

    bobSocket.socket.send(JSON.stringify({
      type: 'call',
      action: 'accept',
      callId
    }));
    bobSocket.socket.send(JSON.stringify({
      type: 'call',
      action: 'accept',
      callId
    }));
    await waitEvent(aliceSocket.events, (event) =>
      event.type === 'call' && event.action === 'accepted' && event.callId === callId,
    '接通同步');
    const activeHealthA = await request(shardA.base, '', 'GET', '/api/health');
    const activeHealthB = await request(shardB.base, '', 'GET', '/api/health');
    assert.equal(activeHealthA.data.activeCalls, 1);
    assert.equal(activeHealthB.data.activeCalls, 0);
    assert.equal(activeHealthB.data.directoryCalls, 1);

    bobSocket.socket.close();
    await new Promise((resolve) => setTimeout(resolve, 700));
    bobSocket = await connect(shardB.base, bob.cookie);
    const reconnected = await waitEvent(bobSocket.events, (event) => event.type === 'ready',
      '通话中重连');
    assert.equal(reconnected.callActive, true);

    const charlie = await login(shardB.base, charlieUser.username);
    charlieSocket = await connect(shardB.base, charlie.cookie);
    const busyCallId = 'call-cross-shard-busy-' + Date.now();
    charlieSocket.socket.send(JSON.stringify({
      type: 'call',
      action: 'invite',
      callId: busyCallId,
      toUserId: alice.user.id,
      media: 'audio'
    }));
    const busy = await waitEvent(charlieSocket.events, (event) =>
      event.type === 'call-error' && event.callId === busyCallId,
    '全局忙线');
    assert.match(busy.error, /正在通话中/);

    const uplink = Buffer.alloc(1282);
    uplink[0] = 0x45;
    uplink[1] = 0x67;
    for (let index = 2; index < uplink.length; index += 1) {
      uplink[index] = index % 251;
    }
    aliceSocket.socket.send(JSON.stringify({
      type: 'call',
      action: 'audio',
      callId,
      data: uplink.toString('base64')
    }));
    const downlink = await waitEvent(bobSocket.events, (event) =>
      event.type === 'call'
      && event.action === 'audio'
      && event.callId === callId,
    '主叫音频');
    assert.equal(downlink.data, uplink.toString('base64'));

    const reply = Buffer.from(uplink);
    reply[200] = 0x7F;
    bobSocket.socket.send(JSON.stringify({
      type: 'call',
      action: 'audio',
      callId,
      data: reply.toString('base64')
    }));
    const replyEvent = await waitEvent(aliceSocket.events, (event) =>
      event.type === 'call'
      && event.action === 'audio'
      && event.callId === callId
      && event.data === reply.toString('base64'),
    '被叫音频');
    assert.equal(replyEvent.peerId, bob.user.id);

    bobSocket.socket.send(JSON.stringify({
      type: 'call',
      action: 'hangup',
      callId
    }));
    const ended = await waitEvent(aliceSocket.events, (event) =>
      event.type === 'call' && event.action === 'end' && event.callId === callId,
    '挂断同步');
    assert.equal(ended.reason, 'hangup');
    const endedHealthA = await request(shardA.base, '', 'GET', '/api/health');
    const endedHealthB = await request(shardB.base, '', 'GET', '/api/health');
    assert.equal(endedHealthA.data.activeCalls, 0);
    assert.equal(endedHealthB.data.directoryCalls, 0);

    const latency = {
      incoming: [],
      accept: [],
      callerAudio: [],
      calleeAudio: []
    };
    for (let round = 0; round < 20; round += 1) {
      const repeatedId = 'call-cross-shard-load-' + round + '-' + Date.now();
      const inviteStarted = Date.now();
      aliceSocket.socket.send(JSON.stringify({
        type: 'call',
        action: 'invite',
        callId: repeatedId,
        toUserId: bob.user.id,
        media: 'audio'
      }));
      await waitEvent(bobSocket.events, (event) =>
        event.type === 'call' && event.action === 'incoming' && event.callId === repeatedId,
      '压力来电');
      latency.incoming.push(Date.now() - inviteStarted);

      const acceptStarted = Date.now();
      bobSocket.socket.send(JSON.stringify({
        type: 'call',
        action: 'accept',
        callId: repeatedId
      }));
      await waitEvent(aliceSocket.events, (event) =>
        event.type === 'call' && event.action === 'accepted' && event.callId === repeatedId,
      '压力接听');
      latency.accept.push(Date.now() - acceptStarted);

      const callerAudioStarted = Date.now();
      aliceSocket.socket.send(JSON.stringify({
        type: 'call',
        action: 'audio',
        callId: repeatedId,
        data: uplink.toString('base64')
      }));
      await waitEvent(bobSocket.events, (event) =>
        event.type === 'call' && event.action === 'audio' && event.callId === repeatedId,
      '压力主叫首帧');
      latency.callerAudio.push(Date.now() - callerAudioStarted);

      const calleeAudioStarted = Date.now();
      bobSocket.socket.send(JSON.stringify({
        type: 'call',
        action: 'audio',
        callId: repeatedId,
        data: reply.toString('base64')
      }));
      await waitEvent(aliceSocket.events, (event) =>
        event.type === 'call' && event.action === 'audio' && event.callId === repeatedId,
      '压力被叫首帧');
      latency.calleeAudio.push(Date.now() - calleeAudioStarted);

      bobSocket.socket.send(JSON.stringify({
        type: 'call',
        action: 'hangup',
        callId: repeatedId
      }));
      await waitEvent(aliceSocket.events, (event) =>
        event.type === 'call' && event.action === 'end' && event.callId === repeatedId,
      '压力挂断');
    }

    const percentile = (values, ratio) => {
      const sorted = values.slice().sort((a, b) => a - b);
      return sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * ratio))];
    };
    const metrics = Object.fromEntries(Object.entries(latency).map(([name, values]) => [
      name,
      {
        p50: percentile(values, 0.5),
        p95: percentile(values, 0.95),
        max: Math.max(...values)
      }
    ]));
    for (const values of Object.values(metrics)) {
      assert.ok(values.p95 < 1000, JSON.stringify(metrics));
      assert.ok(values.max < 2000, JSON.stringify(metrics));
    }

    console.log('call-cross-shard-metrics=' + JSON.stringify(metrics));
    console.log('call-cross-shard: passed');
  } finally {
    aliceSocket?.socket.close();
    bobSocket?.socket.close();
    charlieSocket?.socket.close();
    await stopChild(shardA?.child);
    await stopChild(shardB?.child);
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
