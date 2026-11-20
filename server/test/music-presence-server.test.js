'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const SERVER_DIR = path.resolve(__dirname, '..');
const PASSWORD = 'MusicKernel123!';

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

function makeUser(id, username, nickname) {
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
    salt,
    passwordHash: crypto.scryptSync(PASSWORD, salt, 64).toString('hex'),
    createdAt: new Date(Date.now() - 86400000).toISOString(),
    tokenVersion: 0,
    phoneSession: 0
  };
}

async function call(base, method, endpoint, body, cookie) {
  const headers = {
    'x-device-kind': 'phone',
    'x-device-id': 'music-kernel-test-device'
  };
  if (cookie) headers.Cookie = cookie;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const response = await fetch(base + endpoint, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await response.text();
  const envelope = text ? JSON.parse(text) : {};
  return {
    status: response.status,
    data: envelope.data === undefined ? envelope : envelope.data,
    headers: response.headers
  };
}

async function login(base, username) {
  const response = await call(base, 'POST', '/api/login', {
    username,
    password: PASSWORD
  });
  assert.strictEqual(response.status, 200, JSON.stringify(response.data));
  const raw = response.headers.getSetCookie
    ? response.headers.getSetCookie()[0]
    : response.headers.get('set-cookie') || '';
  return raw.split(';')[0];
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-music-kernel-'));
  const port = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  let child;
  try {
    const users = [
      makeUser('u_music_a', 'music_alice', 'Alice'),
      makeUser('u_music_b', 'music_bob', 'Bob')
    ];
    const createdAt = new Date().toISOString();
    fs.writeFileSync(path.join(dataDir, 'users.json'),
      JSON.stringify({ users }));
    fs.writeFileSync(path.join(dataDir, 'friendships.json'), JSON.stringify({
      friendships: [{
        id: 'f_music_test',
        fromId: 'u_music_a',
        toId: 'u_music_b',
        status: 'accepted',
        createdAt,
        respondedAt: createdAt
      }]
    }));
    fs.writeFileSync(path.join(dataDir, 'security.json'),
      JSON.stringify({ sliderLogin: 0 }));
    fs.writeFileSync(path.join(dataDir, 'ui.json'),
      JSON.stringify({ multiDevice: 1 }));
    fs.writeFileSync(path.join(dataDir, 'chats.json'),
      JSON.stringify({ chats: [] }));

    child = spawn(process.execPath, ['server.js'], {
      cwd: SERVER_DIR,
      env: Object.assign({}, process.env, {
        DATA_DIR: dataDir,
        PORT: String(port),
        TURN_PORT: String(turnPort),
        CHRIS_LOCAL_ONLY: '1',
        PAYMENT_REAL_MONEY_MODE: 'off',
        AML_RUNTIME_ENABLED: '0',
        ADMIN_PASSWORD: 'music-kernel-admin'
      }),
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });
    child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
    child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
    for (let index = 0; index < 220; index += 1) {
      if (child.exitCode !== null) {
        throw new Error('测试服务提前退出：\n' + logs.join(''));
      }
      try {
        if ((await fetch(base + '/api/health')).ok) break;
      } catch (_) { /* starting */ }
      await new Promise((resolve) => setTimeout(resolve, 100));
    }

    const alice = await login(base, 'music_alice');
    const bob = await login(base, 'music_bob');
    let response = await call(base, 'POST', '/api/music/now', {
      id: 'track-1',
      title: '系统级音乐内核',
      artist: '星言',
      cover: '/uploads/cover.jpg',
      url: '/uploads/track.mp3',
      playing: true,
      position: 42.5,
      duration: 180
    }, alice);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));

    response = await call(base, 'GET', '/api/music/friends', undefined, bob);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.list.length, 1);
    assert.strictEqual(response.data.list[0].trackId, 'track-1');
    assert.strictEqual(response.data.list[0].playing, true);
    assert.strictEqual(response.data.list[0].position, 42.5);
    assert.strictEqual(response.data.list[0].duration, 180);

    response = await call(base, 'POST', '/api/music/now', {
      id: 'track-1',
      title: '系统级音乐内核',
      artist: '星言',
      cover: '/uploads/cover.jpg',
      url: '/uploads/track.mp3',
      playing: false,
      position: 55,
      duration: 180
    }, alice);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));

    response = await call(base, 'GET', '/api/music/friends', undefined, bob);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.list[0].playing, false);
    assert.strictEqual(response.data.list[0].position, 55);

    console.log('music-presence-server: passed');
  } finally {
    if (child && child.exitCode === null) child.kill('SIGTERM');
    await new Promise((resolve) => setTimeout(resolve, 250));
    if (process.platform !== 'win32') {
      fs.rmSync(dataDir, { recursive: true, force: true });
    }
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
