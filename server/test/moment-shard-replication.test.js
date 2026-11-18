'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { buildRoutePlan } = require('../lib/shard-route-plan');

const SERVER_DIR = path.resolve(__dirname, '..');
const PASSWORD = 'test123456';
const SECRET = crypto.randomBytes(32).toString('hex');

async function freeBase(count) {
  for (let base = 27000; base < 50000; base += 1) {
    const sockets = [];
    let ok = true;
    for (let index = 0; index < count; index += 1) {
      try {
        await new Promise((resolve, reject) => {
          const server = net.createServer();
          sockets.push(server);
          server.once('error', reject);
          server.listen(base + index * 100, '127.0.0.1', resolve);
        });
      } catch (_) {
        ok = false;
        break;
      }
    }
    await Promise.all(sockets.map((server) => new Promise((resolve) => server.close(resolve))));
    if (ok) return base;
  }
  throw new Error('no free shard port range');
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
    createdAt: new Date().toISOString(),
    tokenVersion: 0,
    phoneSession: 0
  };
}

async function call(base, method, endpoint, body, cookie) {
  const headers = { 'x-device-kind': 'phone' };
  if (cookie) headers.Cookie = cookie;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const response = await fetch(base + endpoint, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const payload = await response.json();
  return {
    status: response.status,
    data: payload && payload.data !== undefined ? payload.data : payload,
    headers: response.headers
  };
}

function cookieOf(response) {
  const raw = response.headers.getSetCookie
    ? response.headers.getSetCookie()[0]
    : response.headers.get('set-cookie') || '';
  return raw.split(';')[0];
}

async function login(base, username) {
  const response = await call(base, 'POST', '/api/login', { username, password: PASSWORD });
  assert.strictEqual(response.status, 200, JSON.stringify(response.data));
  return cookieOf(response);
}

async function startShard(dir, port, basePort, shardId, routePlanFile, routePlanHash) {
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  const child = spawn(process.execPath, ['server.js'], {
    cwd: SERVER_DIR,
    env: Object.assign({}, process.env, {
      DATA_DIR: dir,
      PORT: String(port),
      SHARD_COUNT: '2',
      SHARD_ID: String(shardId),
      SHARD_BASE_PORT: String(basePort),
      SHARD_ROUTE_PLAN_FILE: routePlanFile,
      SHARD_ROUTE_PLAN_FILE_SHA256: routePlanHash,
      SHARD_ROUTE_PLAN_ENFORCED: '0',
      CHRIS_LOCAL_ONLY: '1',
      DISABLE_STARTUP_BOT_BACKFILL: '1',
      AML_RUNTIME_ENABLED: '0'
    }),
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true
  });
  child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
  child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
  for (let i = 0; i < 180; i += 1) {
    if (child.exitCode !== null) throw new Error(logs.join(''));
    try {
      if ((await fetch(base + '/api/health')).ok) return { child, base, logs };
    } catch (_) { /* starting */ }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('shard start timeout\n' + logs.join(''));
}

async function stop(child) {
  if (!child || child.exitCode !== null) return;
  child.kill();
  await new Promise((resolve) => child.once('exit', resolve));
}

async function main() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-moment-replication-'));
  const basePort = await freeBase(2);
  const dirs = [0, 1].map((index) => path.join(root, 'shard-' + index));
  dirs.forEach((dir) => fs.mkdirSync(dir, { recursive: true }));
  const alice = makeUser('u_moment_replication_alice', 'moment_replication_alice');
  const bob = makeUser('u_moment_replication_bob', 'moment_replication_bob');
  const routePlan = buildRoutePlan({
    users: [alice, bob],
    chats: [],
    shardCount: 2,
    ports: [basePort, basePort + 100],
    topologyId: 'moment-replication-2-test',
    baselineDate: '2026-11-16',
    createdAt: '2026-11-16T00:00:00Z'
  });
  const routePlanFile = path.join(root, 'route-plan.json');
  fs.writeFileSync(routePlanFile, JSON.stringify(routePlan, null, 2));
  const routePlanHash = crypto.createHash('sha256')
    .update(fs.readFileSync(routePlanFile)).digest('hex');

  for (const dir of dirs) {
    fs.writeFileSync(path.join(dir, 'secret.key'), SECRET);
    fs.writeFileSync(path.join(dir, 'users.json'), JSON.stringify({ users: [alice, bob] }));
    fs.writeFileSync(path.join(dir, 'friendships.json'), JSON.stringify({
      friendships: [{
        id: 'f_moment_replication',
        fromId: alice.id,
        toId: bob.id,
        status: 'accepted',
        createdAt: new Date().toISOString()
      }]
    }));
    fs.writeFileSync(path.join(dir, 'security.json'), JSON.stringify({ sliderLogin: 0 }));
    fs.writeFileSync(path.join(dir, 'ui.json'), JSON.stringify({ multiDevice: 1 }));
  }

  const servers = [];
  try {
    servers.push(await startShard(dirs[0], basePort, basePort, 0, routePlanFile, routePlanHash));
    servers.push(await startShard(dirs[1], basePort + 100, basePort, 1, routePlanFile, routePlanHash));
    const aliceCookie = await login(servers[0].base, alice.username);
    const bobCookie = await login(servers[1].base, bob.username);

    let response = await call(servers[0].base, 'POST', '/api/moments', {
      content: '跨分片新发布必须可见',
      images: []
    }, aliceCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const momentId = response.data.moment.id;

    response = await call(servers[1].base, 'GET', '/api/moments?limit=20', undefined, bobCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.ok((response.data.moments || []).some((moment) => moment.id === momentId),
      'new moment must be replicated to the other shard');

    response = await call(servers[0].base, 'DELETE', '/api/moments/' + momentId,
      undefined, aliceCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    response = await call(servers[1].base, 'GET', '/api/moments?limit=20', undefined, bobCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.ok(!(response.data.moments || []).some((moment) => moment.id === momentId),
      'deleted moment must not remain visible on the other shard');
    const receiverLog = fs.readFileSync(path.join(dirs[1], 'moments-log.jsonl'), 'utf8');
    assert.ok(receiverLog.includes('"op":"delete"'),
      'the receiver must persist a deletion tombstone');
  } finally {
    for (const server of servers) await stop(server.child);
    fs.rmSync(root, { recursive: true, force: true });
  }
}

main().then(() => {
  console.log('moment-shard-replication: passed');
}).catch((error) => {
  console.error(error.stack || error);
  process.exit(1);
});
