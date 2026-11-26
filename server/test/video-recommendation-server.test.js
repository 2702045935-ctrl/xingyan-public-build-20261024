'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const SERVER_DIR = path.resolve(__dirname, '..');
const PASSWORD = 'VideoKernel123!';

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
    salt,
    passwordHash: crypto.scryptSync(PASSWORD, salt, 64).toString('hex'),
    realNameVerified: false,
    createdAt: new Date(Date.now() - 86400000).toISOString(),
    tokenVersion: 0,
    phoneSession: 0
  };
}

async function call(base, method, endpoint, body, cookie) {
  const headers = {
    'x-device-kind': 'phone',
    'x-device-id': 'video-kernel-test-device'
  };
  if (cookie) headers.Cookie = cookie;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const response = await fetch(base + endpoint, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await response.text();
  let envelope = {};
  try { envelope = text ? JSON.parse(text) : {}; }
  catch (_) { envelope = { raw: text }; }
  return {
    status: response.status,
    data: envelope.data === undefined ? envelope : envelope.data,
    headers: response.headers
  };
}

async function login(base) {
  const response = await call(base, 'POST', '/api/login', {
    username: 'video_viewer',
    password: PASSWORD
  });
  assert.strictEqual(response.status, 200, JSON.stringify(response.data));
  const raw = response.headers.getSetCookie
    ? response.headers.getSetCookie()[0]
    : response.headers.get('set-cookie') || '';
  return raw.split(';')[0];
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-video-server-'));
  const port = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  let child;
  try {
    const viewer = makeUser('video_viewer', 'video_viewer');
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({ users: [viewer] }));
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({ sliderLogin: 0 }));
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }));
    fs.writeFileSync(path.join(dataDir, 'friendships.json'), JSON.stringify({ friendships: [] }));
    fs.writeFileSync(path.join(dataDir, 'chats.json'), JSON.stringify({ chats: [] }));
    const createdAt = new Date().toISOString();
    fs.writeFileSync(path.join(dataDir, 'feed.json'), JSON.stringify({
      items: Array.from({ length: 8 }, (_, index) => ({
        id: 'video-' + index,
        authorId: 'creator-' + (index % 4),
        video: '/uploads/video-' + index + '.mp4',
        cover: '',
        desc: '#AI #topic-' + (index % 3) + ' 视频 ' + index,
        music: 'sound-' + (index % 2),
        createdAt,
        likedBy: [], savedBy: [], comments: [],
        baseLikes: index, baseComments: index % 2, baseShares: index % 3
      })),
      posts: []
    }));
    fs.writeFileSync(path.join(dataDir, 'feed-events.json'), '{broken json');

    child = spawn(process.execPath, ['server.js'], {
      cwd: SERVER_DIR,
      env: Object.assign({}, process.env, {
        DATA_DIR: dataDir,
        PORT: String(port),
        TURN_PORT: String(turnPort),
        CHRIS_LOCAL_ONLY: '1',
        PAYMENT_REAL_MONEY_MODE: 'off',
        AML_RUNTIME_ENABLED: '0',
        ADMIN_PASSWORD: 'video-kernel-admin'
      }),
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });
    child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
    child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
    for (let index = 0; index < 200; index += 1) {
      if (child.exitCode !== null) throw new Error('测试服务提前退出：\n' + logs.join(''));
      try {
        if ((await fetch(base + '/api/health')).ok) break;
      } catch (_) { /* starting */ }
      await new Promise((resolve) => setTimeout(resolve, 100));
    }

    const cookie = await login(base);
    let response = await call(base, 'GET', '/api/feed?tab=recommend', undefined, cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.items.length, 8,
      'a corrupt feedback file must not break feed retrieval');

    response = await call(base, 'POST', '/api/feed/events', {
      events: [
        { eventId: 'event-1', itemId: 'video-0', type: 'impression' },
        { eventId: 'event-2', itemId: 'video-0', type: 'play' },
        {
          eventId: 'event-3',
          itemId: 'video-0',
          type: 'watch',
          watchMs: 12000,
          progress: 0.8
        },
        { eventId: 'event-4', itemId: 'video-0', type: 'like' },
        { eventId: 'event-5', itemId: 'missing-video', type: 'like' },
        { eventId: 'event-6', itemId: 'video-1', type: 'unknown' }
      ]
    }, cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.accepted, 4);
    assert.strictEqual(response.data.rejected, 2);

    response = await call(base, 'POST', '/api/feed/events', {
      events: [{ eventId: 'event-4', itemId: 'video-0', type: 'like' }]
    }, cookie);
    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.data.accepted, 0, 'duplicate events must be ignored');
    assert.strictEqual(response.data.duplicates, 1);

    response = await call(base, 'GET', '/api/feed?tab=recommend', undefined, cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(new Set(response.data.items.map((item) => item.id)).size,
      response.data.items.length);

    console.log('video-recommendation-server: passed');
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
