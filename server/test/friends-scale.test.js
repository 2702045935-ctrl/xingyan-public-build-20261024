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
const TARGET_ID = 'u_friend_scale_owner';

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

function loginUser() {
  const salt = crypto.randomBytes(16).toString('hex');
  return {
    id: TARGET_ID,
    username: 'friend_scale_owner',
    nickname: 'Friend Scale Owner',
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

function publicUser(index) {
  return {
    id: 'u_friend_scale_' + index,
    username: 'friend_scale_' + index,
    nickname: 'Friend ' + index,
    avatar: '',
    bio: '',
    phone: '',
    gender: 'secret',
    balance: 0,
    transferLimit: 20000,
    createdAt: '2026-01-01T00:00:00.000Z',
    tokenVersion: 0,
    phoneSession: 0
  };
}

function friendships(count) {
  return Array.from({ length: count }, (_, index) => ({
    id: 'friend-scale-link-' + index,
    fromId: TARGET_ID,
    toId: 'u_friend_scale_' + index,
    status: 'accepted',
    createdAt: '2026-01-01T00:00:00.000Z',
    respondedAt: '2026-01-01T00:00:00.000Z'
  }));
}

async function waitForHealth(base, child, logs) {
  for (let i = 0; i < 100; i++) {
    if (child.exitCode !== null) {
      throw new Error('测试服务器提前退出：\n' + logs.join(''));
    }
    try {
      const response = await fetch(base + '/api/health');
      if (response.ok) return;
    } catch (_) {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('测试服务器启动超时：\n' + logs.join(''));
}

async function request(base, cookie, url) {
  const started = process.hrtime.bigint();
  const response = await fetch(base + url, {
    method: 'GET',
    headers: cookie
      ? { Cookie: cookie, 'x-device-kind': 'desktop' }
      : { 'x-device-kind': 'desktop' }
  });
  const text = await response.text();
  const elapsedMs = Number(process.hrtime.bigint() - started) / 1e6;
  const envelope = text ? JSON.parse(text) : {};
  return {
    status: response.status,
    data: envelope.data === undefined ? envelope : envelope.data,
    bytes: Buffer.byteLength(text),
    elapsedMs
  };
}

async function login(base) {
  const started = process.hrtime.bigint();
  const response = await fetch(base + '/api/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-device-kind': 'desktop' },
    body: JSON.stringify({ username: 'friend_scale_owner', password: PASSWORD })
  });
  const elapsedMs = Number(process.hrtime.bigint() - started) / 1e6;
  const envelope = await response.json();
  assert.equal(response.status, 200, JSON.stringify(envelope));
  const cookie = (response.headers.getSetCookie
    ? response.headers.getSetCookie()[0]
    : response.headers.get('set-cookie') || '').split(';')[0];
  return { cookie, elapsedMs };
}

async function main() {
  const counts = String(process.env.FRIEND_SCALE_COUNTS || '100,1000,5000,10000')
    .split(',')
    .map((value) => Number(value.trim()))
    .filter((value) => Number.isInteger(value) && value > 0);
  if (!counts.length) throw new Error('FRIEND_SCALE_COUNTS 没有有效数量');
  const maxCount = Math.max(...counts);
  console.error('[friends-scale] seed=' + maxCount);
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-friends-scale-'));
  const port = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const users = [loginUser()];
  for (let index = 0; index < maxCount; index++) users.push(publicUser(index));

  fs.writeFileSync(path.join(dataDir, 'users.json'),
    JSON.stringify({ users }), 'utf8');
  fs.writeFileSync(path.join(dataDir, 'security.json'),
    JSON.stringify({ sliderLogin: 0 }), 'utf8');
  fs.writeFileSync(path.join(dataDir, 'ui.json'),
    JSON.stringify({ multiDevice: 1 }), 'utf8');

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

  try {
    console.error('[friends-scale] starting server');
    await waitForHealth(base, child, logs);
    console.error('[friends-scale] server ready');
    const session = await login(base);
    console.error('[friends-scale] login=' + Math.round(session.elapsedMs * 10) / 10 + 'ms');
    const results = [];

    for (const count of counts) {
      fs.writeFileSync(path.join(dataDir, 'friendships.json'),
        JSON.stringify({ friendships: friendships(count) }), 'utf8');
      const response = await request(base, session.cookie, '/api/contacts');
      assert.equal(response.status, 200, JSON.stringify(response.data));
      assert.equal((response.data.friends || []).length, count,
        `好友数量不一致：expected ${count}, got ${(response.data.friends || []).length}`);
      const unique = new Set((response.data.friends || []).map((friend) => friend.id));
      assert.equal(unique.size, count, '通讯录出现重复好友');
      results.push({
        friends: count,
        responseFriends: (response.data.friends || []).length,
        responseBytes: response.bytes,
        elapsedMs: Math.round(response.elapsedMs * 10) / 10
      });
      console.error('[friends-scale] ' + count + '=' + Math.round(response.elapsedMs * 10) / 10 + 'ms');
    }

    console.log(JSON.stringify({
      loginMs: Math.round(session.elapsedMs * 10) / 10,
      results
    }));
    console.log('friends-scale: passed');
  } finally {
    if (child.exitCode === null) {
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
