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

async function call(base, cookie, method, route, body, deviceId) {
  const headers = {
    'x-device-kind': 'phone',
    'x-device-id': deviceId || 'device-sync-phone'
  };
  if (cookie) headers.Cookie = cookie;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const response = await fetch(base + route, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await response.text();
  let json = {};
  try { json = text ? JSON.parse(text) : {}; }
  catch (_) { json = { raw: text }; }
  return {
    status: response.status,
    data: json && json.data !== undefined ? json.data : json,
    headers: response.headers
  };
}

async function login(base, username, deviceId) {
  const response = await call(base, '', 'POST', '/api/login', {
    username,
    password: PASSWORD
  }, deviceId);
  assert.strictEqual(response.status, 200, JSON.stringify(response.data));
  const cookie = (response.headers.getSetCookie
    ? response.headers.getSetCookie()[0]
    : response.headers.get('set-cookie') || '').split(';')[0];
  return { cookie, user: response.data.user };
}

async function startServer(dataDir) {
  const port = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  const child = spawn(process.execPath, ['server.js'], {
    cwd: SERVER_DIR,
    env: Object.assign({}, process.env, {
      DATA_DIR: dataDir,
      PORT: String(port),
      TURN_PORT: String(await freePort()),
      CHRIS_LOCAL_ONLY: '1',
      MESSAGE_RELIABILITY_ENABLED: '1',
      MESSAGE_RELIABILITY_BACKFILL: '0'
    }),
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true
  });
  child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
  child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
  for (let index = 0; index < 120; index += 1) {
    if (child.exitCode !== null) throw new Error('server exited:\n' + logs.join(''));
    try {
      if ((await fetch(base + '/api/health')).ok) return { child, base, logs };
    } catch (_) { /* retry */ }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('server start timeout:\n' + logs.join(''));
}

async function stopServer(child) {
  if (child && child.exitCode === null) child.kill();
  await new Promise((resolve) => setTimeout(resolve, 350));
}

function syncItem(page, chatId) {
  return (page.items || []).find((item) => item.chatId === chatId);
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-device-sync-'));
  let child;
  try {
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [
        user('u_sync_alice', 'sync_alice', 'Alice'),
        user('u_sync_bob', 'sync_bob', 'Bob'),
        user('u_sync_carol', 'sync_carol', 'Carol')
      ]
    }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'security.json'),
      JSON.stringify({ sliderLogin: 0 }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'ui.json'),
      JSON.stringify({ multiDevice: 1 }, null, 2));

    let running = await startServer(dataDir);
    child = running.child;
    let base = running.base;
    const alice = await login(base, 'sync_alice', 'alice-phone');
    const bobPhone = await login(base, 'sync_bob', 'bob-phone');
    const bobDesktop = await login(base, 'sync_bob', 'bob-desktop');
    const carol = await login(base, 'sync_carol', 'carol-phone');

    let response = await call(base, alice.cookie, 'POST', '/api/chats/direct', {
      userId: bobPhone.user.id
    }, 'alice-phone');
    const aliceChat = response.data.chat.id;
    response = await call(base, carol.cookie, 'POST', '/api/chats/direct', {
      userId: bobPhone.user.id
    }, 'carol-phone');
    const carolChat = response.data.chat.id;

    for (let index = 1; index <= 3; index += 1) {
      response = await call(base, alice.cookie, 'POST',
        `/api/chats/${aliceChat}/messages`, {
          kind: 'text',
          content: `sync ${index}`,
          clientId: `sync-${index}`
        }, 'alice-phone');
      assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    }

    response = await call(base, bobPhone.cookie, 'GET',
      '/api/sync/state?limit=1', undefined, 'bob-phone');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.enabled, true);
    assert.strictEqual(response.data.items.length, 1);
    assert.strictEqual(response.data.hasMore, true);
    assert.ok(response.data.nextCursor);

    const firstIds = new Set(response.data.items.map((item) => item.chatId));
    let cursor = response.data.nextCursor;
    while (cursor) {
      response = await call(base, bobPhone.cookie, 'GET',
        `/api/sync/state?limit=1&cursor=${encodeURIComponent(cursor)}`,
        undefined, 'bob-phone');
      assert.strictEqual(response.status, 200, JSON.stringify(response.data));
      response.data.items.forEach((item) => firstIds.add(item.chatId));
      cursor = response.data.hasMore ? response.data.nextCursor : '';
    }
    assert.ok(firstIds.has(aliceChat));
    assert.ok(firstIds.has(carolChat));

    response = await call(base, bobPhone.cookie, 'GET',
      '/api/sync/state?limit=200', undefined, 'bob-phone');
    const before = syncItem(response.data, aliceChat);
    assert.strictEqual(before.lastSeq, 3);
    assert.strictEqual(before.deliveredSeq, 0);
    assert.strictEqual(before.hasDelta, true);

    response = await call(base, bobPhone.cookie, 'POST', '/api/sync/ack', {
      items: [{ chatId: aliceChat, seq: 2 }]
    }, 'bob-phone');
    assert.strictEqual(response.data.acknowledged, 1);
    response = await call(base, bobPhone.cookie, 'GET',
      '/api/sync/state?limit=200', undefined, 'bob-phone');
    assert.strictEqual(syncItem(response.data, aliceChat).deliveredSeq, 2);

    response = await call(base, bobPhone.cookie, 'POST', '/api/sync/ack', {
      items: [{ chatId: aliceChat, seq: 99 }]
    }, 'bob-phone');
    assert.strictEqual(response.data.acknowledged, 0);
    assert.strictEqual(response.data.rejected[0].reason, 'sequence-out-of-range');

    response = await call(base, bobPhone.cookie, 'POST',
      `/api/chats/${aliceChat}/read`, {}, 'bob-phone');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    response = await call(base, bobDesktop.cookie, 'GET',
      '/api/sync/state?limit=200', undefined, 'bob-desktop');
    const desktop = syncItem(response.data, aliceChat);
    assert.strictEqual(desktop.readSeq, 3);
    assert.strictEqual(desktop.deliveredSeq, 0);
    assert.strictEqual(desktop.hasDelta, true);

    response = await call(base, bobDesktop.cookie, 'POST', '/api/sync/ack', {
      items: [{ chatId: aliceChat, seq: 3 }]
    }, 'bob-desktop');
    assert.strictEqual(response.data.acknowledged, 1);

    const token = 'ab'.repeat(32);
    response = await call(base, bobPhone.cookie, 'POST', '/api/push/register', {
      token,
      platform: 'ios',
      env: 'sandbox',
      deviceId: 'bob-phone'
    }, 'bob-phone');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.devices, 1);
    response = await call(base, bobPhone.cookie, 'POST', '/api/push/register', {
      token,
      platform: 'ios',
      env: 'sandbox',
      deviceId: 'bob-phone'
    }, 'bob-phone');
    assert.strictEqual(response.data.devices, 1);

    response = await call(base, bobPhone.cookie, 'DELETE',
      `/api/chats/${carolChat}?clear=1`, undefined, 'bob-phone');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    response = await call(base, bobDesktop.cookie, 'GET',
      '/api/message-events?after=0&limit=500', undefined, 'bob-desktop');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.ok(response.data.events.some((event) =>
      event.type === 'chat.removed'
      && event.payload.chatId === carolChat
      && event.payload.ownerId === bobPhone.user.id));

    await stopServer(child);
    running = await startServer(dataDir);
    child = running.child;
    base = running.base;
    response = await call(base, bobDesktop.cookie, 'GET',
      '/api/sync/state?limit=200', undefined, 'bob-desktop');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(syncItem(response.data, aliceChat).deliveredSeq, 3);

    console.log('device-sync-state: passed');
  } finally {
    await stopServer(child);
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
