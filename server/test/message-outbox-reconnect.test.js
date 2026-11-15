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
    'x-device-kind': 'desktop',
    'x-device-id': deviceId || 'outbox-device'
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
  await new Promise((resolve) => setTimeout(resolve, 400));
}

async function send(base, session, chatId, clientId, content) {
  const response = await call(base, session.cookie, 'POST',
    `/api/chats/${chatId}/messages`, {
      kind: 'text',
      content,
      clientId
    }, 'alice-phone');
  assert.strictEqual(response.status, 200, JSON.stringify(response.data));
  return response.data.message;
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-outbox-reconnect-'));
  let child;
  try {
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [
        user('u_outbox_alice', 'outbox_alice', 'Alice'),
        user('u_outbox_bob', 'outbox_bob', 'Bob')
      ]
    }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'security.json'),
      JSON.stringify({ sliderLogin: 0 }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'ui.json'),
      JSON.stringify({ multiDevice: 1 }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'im.json'),
      JSON.stringify({ allowStranger: true }, null, 2));

    let running = await startServer(dataDir);
    child = running.child;
    let base = running.base;
    const alice = await login(base, 'outbox_alice', 'alice-phone');
    const bob = await login(base, 'outbox_bob', 'bob-phone');

    let response = await call(base, alice.cookie, 'POST', '/api/chats/direct', {
      userId: bob.user.id
    }, 'alice-phone');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const chatId = response.data.chat.id;

    const first = await send(base, alice, chatId, 'outbox-client-1', 'first queued');
    const second = await send(base, alice, chatId, 'outbox-client-2', 'second queued');
    assert.strictEqual(first.seq, 1);
    assert.strictEqual(second.seq, 2);

    const lateRetry = await send(
      base, alice, chatId, 'outbox-client-1', 'first queued retry payload'
    );
    assert.strictEqual(lateRetry.id, first.id);
    assert.strictEqual(lateRetry.seq, 1);
    assert.strictEqual(lateRetry.content, 'first queued');

    const concurrent = await Promise.all(Array.from({ length: 8 }, (_, index) =>
      send(base, alice, chatId, 'outbox-client-3', 'third queued ' + index)
    ));
    assert.strictEqual(new Set(concurrent.map((row) => row.id)).size, 1);
    assert.strictEqual(new Set(concurrent.map((row) => row.seq)).size, 1);
    assert.strictEqual(concurrent[0].seq, 3);
    assert.strictEqual(concurrent[0].content, 'third queued 0');

    const fourth = await send(base, alice, chatId, 'outbox-client-4', 'fourth queued');
    assert.strictEqual(fourth.seq, 4);
    const reply = await send(base, bob, chatId, 'bob-reply-1', 'bob reply');
    assert.strictEqual(reply.seq, 5);

    await stopServer(child);
    running = await startServer(dataDir);
    child = running.child;
    base = running.base;

    const retrySecond = await send(
      base, alice, chatId, 'outbox-client-2', 'second queued retry payload'
    );
    const retryThird = await send(
      base, alice, chatId, 'outbox-client-3', 'third queued retry payload'
    );
    assert.strictEqual(retrySecond.id, second.id);
    assert.strictEqual(retrySecond.seq, 2);
    assert.strictEqual(retryThird.id, concurrent[0].id);
    assert.strictEqual(retryThird.seq, 3);
    const fifth = await send(base, alice, chatId, 'outbox-client-5', 'fifth queued');
    assert.strictEqual(fifth.seq, 6);

    response = await call(base, bob.cookie, 'GET',
      `/api/chats/${chatId}/messages?since=0&limit=100`, undefined, 'bob-phone');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const messages = response.data.messages;
    assert.deepStrictEqual(messages.map((row) => row.seq), [1, 2, 3, 4, 5, 6]);
    assert.strictEqual(new Set(messages.map((row) => row.id)).size, messages.length);
    assert.strictEqual(
      new Set(messages.map((row) => row.clientId).filter(Boolean)).size,
      messages.length
    );
    assert.deepStrictEqual(
      messages.map((row) => row.content),
      [
        'first queued',
        'second queued',
        'third queued 0',
        'fourth queued',
        'bob reply',
        'fifth queued'
      ]
    );

    response = await call(base, bob.cookie, 'GET',
      '/api/message-events?after=0&limit=100', undefined, 'bob-phone');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const created = response.data.events.filter((event) =>
      event.type === 'message.created'
      && event.payload
      && event.payload.chatId === chatId
    );
    assert.strictEqual(created.length, messages.length,
      JSON.stringify(created.map((event) => ({
        type: event.type,
        entityId: event.entityId,
        version: event.version,
        sequence: event.sequence,
        chatId: event.payload && event.payload.chatId,
        content: event.payload && event.payload.content
      }))));
    assert.strictEqual(new Set(created.map((event) => event.entityId)).size, messages.length);
    assert.deepStrictEqual(
      created.map((event) => event.version).sort((left, right) => left - right),
      [1, 2, 3, 4, 5, 6]
    );

    console.log('message-outbox-reconnect: passed');
  } finally {
    await stopServer(child);
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
