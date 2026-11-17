'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');
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
  for (let index = 0; index < 120; index += 1) {
    if (child.exitCode !== null) {
      throw new Error('authority server exited early:\n' + logs.join(''));
    }
    try {
      const response = await fetch(base + '/api/health');
      if (response.ok) return;
    } catch (_) {
      // Starting.
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('authority server start timeout:\n' + logs.join(''));
}

function startServer(dataDir, port, turnPort, logs) {
  const child = spawn(process.execPath, ['server.js'], {
    cwd: SERVER_DIR,
    env: Object.assign({}, process.env, {
      DATA_DIR: dataDir,
      PORT: String(port),
      TURN_PORT: String(turnPort),
      CHRIS_LOCAL_ONLY: '1',
      SHARD_AUTHORITY_ENABLED: '1',
      SHARD_AUTHORITY_READ: '1',
      SHARD_AUTHORITY_WRITE: '1',
      SHARD_AUTHORITY_DB_FILE: path.join(dataDir, 'shard-authority.sqlite3'),
      SHARD_AUTHORITY_EPOCH: '1',
      SHARD_ID: '0',
      SHARD_TOPOLOGY_ID: 'server-b-mainline-shards-7'
    }),
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true
  });
  child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
  child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
  return child;
}

async function call(base, cookie, method, route, body) {
  const headers = { 'x-device-kind': 'desktop' };
  if (cookie) headers.Cookie = cookie;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const response = await fetch(base + route, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const envelope = await response.json();
  return {
    status: response.status,
    data: envelope && envelope.data !== undefined ? envelope.data : envelope,
    headers: response.headers
  };
}

async function login(base, username) {
  const response = await call(base, '', 'POST', '/api/login', {
    username,
    password: PASSWORD
  });
  assert.strictEqual(response.status, 200, JSON.stringify(response.data));
  const setCookie = response.headers.getSetCookie
    ? response.headers.getSetCookie()[0]
    : response.headers.get('set-cookie') || '';
  return {
    cookie: setCookie.split(';')[0],
    user: response.data.user
  };
}

async function stopChild(child) {
  if (!child || child.exitCode !== null) return;
  child.kill('SIGTERM');
  for (let index = 0; index < 60; index += 1) {
    if (child.exitCode !== null) return;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  child.kill('SIGKILL');
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-authority-server-'));
  const logs = [];
  const port = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  let child = null;
  try {
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [
        user('u_authority_alice', 'authority_alice', 'Authority Alice'),
        user('u_authority_bob', 'authority_bob', 'Authority Bob')
      ]
    }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'security.json'),
      JSON.stringify({ sliderLogin: 0 }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'ui.json'),
      JSON.stringify({ multiDevice: 1 }, null, 2));

    child = startServer(dataDir, port, turnPort, logs);
    await waitForHealth(base, child, logs);
    assert.ok(logs.join('').includes('[分片权威] 已启用'), 'authority mode did not start');

    const alice = await login(base, 'authority_alice');
    const bob = await login(base, 'authority_bob');
    let response = await call(base, alice.cookie, 'POST', '/api/friends/request', {
      username: 'authority_bob',
      message: 'authority test'
    });
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    response = await call(base, bob.cookie, 'GET', '/api/contacts');
    const request = (response.data.incoming || [])[0];
    assert.ok(request && request.requestId);
    response = await call(base, bob.cookie, 'POST', '/api/friends/respond', {
      requestId: request.requestId,
      accept: true
    });
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const chatId = response.data.chat.id;

    response = await call(base, bob.cookie, 'POST',
      '/api/chats/' + chatId + '/messages', {
        kind: 'text',
        content: 'authority-primary-message',
        clientId: 'authority-client-1'
      });
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));

    const databaseFile = path.join(dataDir, 'shard-authority.sqlite3');
    const db = new DatabaseSync(databaseFile, { readOnly: true });
    const row = db.prepare(`
      SELECT message_id, seq, payload_json
      FROM reliable_messages
      WHERE chat_id = ?
      ORDER BY seq DESC LIMIT 1
    `).get(chatId);
    db.close();
    assert.ok(row, 'message missing from authority database');
    assert.strictEqual(JSON.parse(row.payload_json).content, 'authority-primary-message');

    // Remove the compatibility JSONL. A primary read must still return the
    // authority row, proving the cutover path is active rather than shadow-only.
    const messageFile = path.join(dataDir, 'messages', chatId + '.jsonl');
    if (fs.existsSync(messageFile)) fs.rmSync(messageFile);
    response = await call(base, bob.cookie, 'GET',
      '/api/chats/' + chatId + '/messages?all=1');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.ok((response.data.messages || []).some((message) =>
      message.content === 'authority-primary-message'
    ), 'authority read path did not survive compatibility file removal');

    await stopChild(child);
    child = startServer(dataDir, port, turnPort, logs);
    await waitForHealth(base, child, logs);
    const bobAgain = await login(base, 'authority_bob');
    response = await call(base, bobAgain.cookie, 'GET',
      '/api/chats/' + chatId + '/messages?all=1');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.ok((response.data.messages || []).some((message) =>
      message.content === 'authority-primary-message'
    ), 'authority primary message did not survive restart');
    console.log('shard-authority-server: passed');
  } finally {
    await stopChild(child);
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
