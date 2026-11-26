'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const http2 = require('http2');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const SERVER_DIR = path.resolve(__dirname, '..');
const PASSWORD = 'PushBurst10000!';
const TARGETS = 10000;
const RETRY_TARGETS = 10;
const INVALID_TARGETS = 10;
const CHAT_ID = 'c_push_burst_10000';

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const found = process.argv.slice(2).find((item) => item.startsWith(prefix));
  return found ? found.slice(prefix.length) : fallback;
}

function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const port = server.address().port;
      server.close(() => resolve(port));
    });
  });
}

function tokenFor(index, prefix) {
  const raw = prefix + index.toString(16);
  return raw.padEnd(64, index % 10 === 0 ? 'a' : 'b').slice(0, 64);
}

function account(index, includePassword) {
  const id = index === 0 ? 'u_push_sender' : 'u_push_target_' + index;
  const user = {
    id,
    username: index === 0 ? 'push_sender' : 'push_target_' + index,
    nickname: index === 0 ? 'Push Sender' : 'Push Target ' + index,
    avatar: '',
    bio: '',
    phone: '',
    gender: 'secret',
    balance: 0,
    transferLimit: 20000,
    createdAt: '2026-01-01T00:00:00.000Z',
    tokenVersion: 0,
    phoneSession: 0,
    notify: {
      on: true,
      sound: true,
      showDetail: true
    }
  };
  if (includePassword) {
    const salt = crypto.randomBytes(16).toString('hex');
    user.salt = salt;
    user.passwordHash = crypto.scryptSync(PASSWORD, salt, 64).toString('hex');
  }
  return user;
}

function processMemoryMb(pid) {
  const result = require('child_process').spawnSync('powershell.exe', [
    '-NoProfile',
    '-Command',
    '(Get-Process -Id ' + Number(pid) + ' -ErrorAction Stop).WorkingSet64'
  ], { encoding: 'utf8', timeout: 5000, windowsHide: true });
  const value = Number(String(result.stdout || '').trim());
  return Number.isFinite(value) && value > 0
    ? Math.round(value / 1024 / 1024)
    : null;
}

async function waitForHealth(base, child, logs) {
  for (let index = 0; index < 300; index += 1) {
    if (child.exitCode !== null) {
      throw new Error('push-burst server exited:\n' + logs.join(''));
    }
    try {
      if ((await fetch(base + '/api/health')).ok) return;
    } catch (_) {
      // The 10k fixture is still loading.
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('push-burst server start timeout:\n' + logs.join(''));
}

async function call(base, cookie, method, url, body) {
  const headers = {
    'x-device-kind': 'desktop',
    'x-device-id': 'push-burst-test'
  };
  if (cookie) headers.Cookie = cookie;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const response = await fetch(base + url, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await response.text();
  let envelope = {};
  try { envelope = text ? JSON.parse(text) : {}; } catch (_) { envelope = { raw: text }; }
  const data = envelope && envelope.data !== undefined ? envelope.data : envelope;
  return { status: response.status, data, headers: response.headers };
}

async function login(base, username) {
  const response = await call(base, '', 'POST', '/api/login', {
    username,
    password: PASSWORD
  });
  assert.strictEqual(response.status, 200, JSON.stringify(response.data));
  const cookie = (response.headers.getSetCookie
    ? response.headers.getSetCookie()[0]
    : response.headers.get('set-cookie') || '').split(';')[0];
  assert.ok(cookie, 'login did not return a session cookie');
  return cookie;
}

function createFakeApns() {
  const state = {
    connections: 0,
    requests: 0,
    active: 0,
    maxActive: 0,
    retries: new Map(),
    invalidResponses: 0,
    transientResponses: 0,
    accepted: 0
  };
  const server = http2.createServer();
  server.on('session', () => {
    state.connections += 1;
  });
  server.on('stream', (stream, headers) => {
    state.requests += 1;
    state.active += 1;
    state.maxActive = Math.max(state.maxActive, state.active);
    let closed = false;
    const finish = () => {
      if (closed) return;
      closed = true;
      state.active -= 1;
    };
    stream.on('close', finish);
    stream.on('error', finish);
    stream.resume();
    const token = String(headers[':path'] || '').split('/').pop();
    if (token.includes('invalid')) {
      state.invalidResponses += 1;
      stream.respond({ ':status': 410, 'content-type': 'application/json' });
      stream.end('{"reason":"Unregistered"}');
      return;
    }
    if (token.includes('retry')) {
      const attempts = (state.retries.get(token) || 0) + 1;
      state.retries.set(token, attempts);
      if (attempts < 3) {
        state.transientResponses += 1;
        stream.respond({ ':status': attempts === 1 ? 500 : 429, 'content-type': 'application/json' });
        stream.end('{"reason":"ServiceUnavailable"}');
        return;
      }
    }
    state.accepted += 1;
    stream.respond({ ':status': 200 });
    stream.end();
  });
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      resolve({
        server,
        state,
        base: 'http://127.0.0.1:' + server.address().port
      });
    });
  });
}

async function waitFor(predicate, timeoutMs, label) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error(label + ' timeout');
}

async function main() {
  const out = arg('out', '');
  const fake = await createFakeApns();
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-push-burst-'));
  const logs = [];
  let child = null;
  const startedAt = Date.now();
  try {
    fs.mkdirSync(path.join(dataDir, 'messages'), { recursive: true });
    const users = Array.from(
      { length: TARGETS + 1 },
      (_, index) => account(index, index === 0)
    );
    const recipients = users.slice(1);
    const tokens = {};
    recipients.forEach((user, index) => {
      let prefix = 'normal_';
      if (index < INVALID_TARGETS) prefix = 'invalid_';
      else if (index < INVALID_TARGETS + RETRY_TARGETS) prefix = 'retry_';
      tokens[user.id] = [{
        token: tokenFor(index, prefix),
        env: 'prod',
        platform: 'ios',
        deviceId: 'push-burst-' + index,
        updatedAt: '2026-01-01T00:00:00.000Z'
      }];
    });
    const key = crypto.generateKeyPairSync('ec', {
      namedCurve: 'P-256'
    }).privateKey.export({
      format: 'pem',
      type: 'pkcs8'
    });
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({ users }), 'utf8');
    fs.writeFileSync(path.join(dataDir, 'friendships.json'), JSON.stringify({ friendships: [] }), 'utf8');
    fs.writeFileSync(path.join(dataDir, 'chats.json'), JSON.stringify({
      chats: [{
        id: CHAT_ID,
        type: 'group',
        name: '10K offline push',
        avatar: '',
        memberIds: users.map((user) => user.id),
        ownerId: users[0].id,
        seq: 0,
        createdAt: '2026-01-01T00:00:00.000Z',
        pinnedFor: [],
        mutedFor: [],
        muteMembers: [],
        aliases: {}
      }]
    }), 'utf8');
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({ sliderLogin: 0 }), 'utf8');
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }), 'utf8');
    fs.writeFileSync(path.join(dataDir, 'im.json'), JSON.stringify({
      allowStranger: true,
      maxGroupMembers: TARGETS + 1
    }), 'utf8');
    fs.writeFileSync(path.join(dataDir, 'push.json'), JSON.stringify({
      config: {
        enabled: true,
        bundleId: 'com.chris.chatnative',
        teamId: 'PUSHTEST01',
        keyId: 'PUSHTEST01',
        keyText: key,
        sandbox: false,
        onMessage: true,
        onFriend: true,
        onCall: true
      },
      tokens
    }), 'utf8');

    const port = await freePort();
    const turnPort = await freePort();
    const base = 'http://127.0.0.1:' + port;
    child = spawn(process.execPath, ['server.js'], {
      cwd: SERVER_DIR,
      env: Object.assign({}, process.env, {
        DATA_DIR: dataDir,
        PORT: String(port),
        TURN_PORT: String(turnPort),
        CHRIS_LOCAL_ONLY: '1',
        AML_RUNTIME_ENABLED: '0',
        DISABLE_STARTUP_BOT_BACKFILL: '1',
        MESSAGE_RELIABILITY_ENABLED: '1',
        APNS_PRODUCTION_HOST: fake.base,
        APNS_MAX_IN_FLIGHT: '32',
        APNS_REQUEST_TIMEOUT_MS: '5000',
        PUSH_USER_CONCURRENCY: '64'
      }),
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });
    child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
    child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
    await waitForHealth(base, child, logs);
    const cookie = await login(base, users[0].username);
    const response = await call(
      base,
      cookie,
      'POST',
      '/api/chats/' + CHAT_ID + '/messages',
      {
        kind: 'text',
        content: 'offline push burst',
        clientId: 'push-burst-1',
        mentions: []
      }
    );
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    await waitFor(
      () => fake.state.requests >= TARGETS + (RETRY_TARGETS * 2),
      60000,
      'fake APNs requests'
    );
    await waitFor(
      () => fake.state.active === 0,
      20000,
      'fake APNs drain'
    );
    await new Promise((resolve) => setTimeout(resolve, 400));

    const persisted = JSON.parse(fs.readFileSync(path.join(dataDir, 'push.json'), 'utf8'));
    const invalidIds = new Set(recipients.slice(0, INVALID_TARGETS).map((user) => user.id));
    const remainingInvalid = Array.from(invalidIds).filter((id) => persisted.tokens[id]);
    const retryTokens = Array.from(fake.state.retries.entries());
    const failedRetries = retryTokens.filter(([, attempts]) => attempts !== 3);
    const logPath = path.join(dataDir, 'push-log.jsonl');
    const logLines = fs.existsSync(logPath)
      ? fs.readFileSync(logPath, 'utf8').trim().split('\n').filter(Boolean).length
      : 0;
    const result = {
      scope: 'Isolated fake APNs HTTP/2 server, temporary 10k-member group, no production traffic',
      targets: TARGETS,
      retryTargets: RETRY_TARGETS,
      invalidTargets: INVALID_TARGETS,
      totalRequests: fake.state.requests,
      accepted: fake.state.accepted,
      transientResponses: fake.state.transientResponses,
      invalidResponses: fake.state.invalidResponses,
      http2Connections: fake.state.connections,
      maxConcurrentStreams: fake.state.maxActive,
      retryAttemptsExact: failedRetries.length === 0,
      invalidTokensRemoved: remainingInvalid.length === 0,
      pushLogLines: logLines,
      elapsedMs: Date.now() - startedAt,
      serverMemoryMb: processMemoryMb(child.pid),
      pass: fake.state.requests >= TARGETS + (RETRY_TARGETS * 2)
        && failedRetries.length === 0
        && remainingInvalid.length === 0
        && fake.state.connections <= 2
        && fake.state.maxActive <= 32
        && logLines <= 300
    };
    console.log(JSON.stringify(result, null, 2));
    if (out) {
      fs.mkdirSync(path.dirname(path.resolve(out)), { recursive: true });
      fs.writeFileSync(path.resolve(out), JSON.stringify(result, null, 2) + '\n', 'utf8');
    }
    if (!result.pass) process.exitCode = 2;
    else console.log('push-burst: passed');
  } finally {
    if (child && child.exitCode === null) child.kill();
    await new Promise((resolve) => setTimeout(resolve, 200));
    fake.server.close();
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
