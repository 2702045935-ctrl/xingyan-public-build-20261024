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
  for (let index = 0; index < 150; index += 1) {
    if (child.exitCode !== null) {
      throw new Error('测试服务提前退出：\n' + logs.join(''));
    }
    try {
      if ((await fetch(base + '/api/health')).ok) return;
    } catch (_) {
      // 等待服务启动。
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('测试服务启动超时：\n' + logs.join(''));
}

async function request(base, cookie, method, url, body) {
  const headers = { 'x-device-kind': 'phone' };
  if (cookie) headers.Cookie = cookie;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const response = await fetch(base + url, {
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
      // 忽略无法解析的事件。
    }
  });
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('WebSocket 连接超时')), 5000);
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
        // 忽略无法解析的事件。
      }
    });
  });
}

async function waitEvent(events, predicate) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    const found = events.find(predicate);
    if (found) return found;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error('等待通话事件超时：' + JSON.stringify(events.slice(-20)));
}

async function startServer(dataDir, port, turnPort) {
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  const child = spawn(process.execPath, ['server.js'], {
    cwd: SERVER_DIR,
    env: Object.assign({}, process.env, {
      DATA_DIR: dataDir,
      PORT: String(port),
      TURN_PORT: String(turnPort),
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

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-call-audio-'));
  const port = await freePort();
  const turnPort = await freePort();
  let child;
  let aliceSocket;
  let bobSocket;

  try {
    const aliceUser = user('u_call_audio_alice', 'call_audio_alice', 'Alice');
    const bobUser = user('u_call_audio_bob', 'call_audio_bob', 'Bob');
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [aliceUser, bobUser]
    }));
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({ sliderLogin: 0 }));
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }));
    fs.writeFileSync(path.join(dataDir, 'friendships.json'), JSON.stringify({
      friendships: [{
        id: 'friend-call-audio',
        fromId: aliceUser.id,
        toId: bobUser.id,
        status: 'accepted',
        createdAt: new Date().toISOString()
      }]
    }));
    fs.writeFileSync(path.join(dataDir, 'chats.json'), JSON.stringify({
      chats: [{
        id: 'c_call_audio',
        type: 'direct',
        memberIds: [aliceUser.id, bobUser.id],
        seq: 0,
        createdAt: new Date().toISOString()
      }]
    }));

    const server = await startServer(dataDir, port, turnPort);
    child = server.child;
    const alice = await login(server.base, aliceUser.username);
    const bob = await login(server.base, bobUser.username);
    aliceSocket = await connect(server.base, alice.cookie);
    bobSocket = await connect(server.base, bob.cookie);

    const callId = 'call-audio-relay-test';
    aliceSocket.socket.send(JSON.stringify({
      type: 'call',
      action: 'invite',
      callId,
      toUserId: bob.user.id,
      media: 'audio'
    }));
    const inviteResult = await waitEvent(aliceSocket.events, (event) =>
      (event.type === 'call' && event.action === 'ringing')
      || event.type === 'call-error').catch((error) => {
      console.error(server.logs.join(''));
      throw error;
    });
    assert.equal(inviteResult.type, 'call', JSON.stringify(inviteResult));
    assert.equal(inviteResult.action, 'ringing', JSON.stringify(inviteResult));
    await waitEvent(bobSocket.events, (event) =>
      event.type === 'call' && event.action === 'incoming' && event.callId === callId);

    bobSocket.socket.send(JSON.stringify({
      type: 'call',
      action: 'accept',
      callId
    }));
    await waitEvent(aliceSocket.events, (event) =>
      event.type === 'call' && event.action === 'accepted' && event.callId === callId);

    const uplink = Buffer.alloc(1282);
    uplink[0] = 0x12;
    uplink[1] = 0x34;
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
      && event.callId === callId);
    assert.equal(downlink.data, uplink.toString('base64'));

    const reply = Buffer.from(uplink);
    reply[100] = 0x7F;
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
      && event.data === reply.toString('base64'));
    assert.equal(replyEvent.peerId, bob.user.id);

    console.log('call-audio-relay: passed');
  } finally {
    aliceSocket?.socket.close();
    bobSocket?.socket.close();
    if (child && child.exitCode === null) {
      const exited = new Promise((resolve) => child.once('exit', resolve));
      child.kill();
      await Promise.race([
        exited,
        new Promise((resolve) => setTimeout(resolve, 3000))
      ]);
    }
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
