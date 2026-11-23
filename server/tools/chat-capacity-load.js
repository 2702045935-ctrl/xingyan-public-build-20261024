#!/usr/bin/env node
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn, spawnSync } = require('child_process');

const SERVER_DIR = path.resolve(__dirname, '..');
const CHAT_ID = 'c_capacity_load';
const TOKEN_COOKIE = 'chris_chat_session';
const secret = process.env.CAPACITY_LOAD_SECRET || crypto.randomBytes(32).toString('hex');
let activeLogs = [];

function arg(name, fallback) {
  const prefix = `--${name}=`;
  const value = process.argv.slice(2).find((item) => item.startsWith(prefix));
  return value ? value.slice(prefix.length) : fallback;
}

function percentile(values, fraction) {
  if (!values.length) return null;
  const sorted = values.slice().sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * fraction) - 1)];
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

function portAvailable(port) {
  return new Promise((resolve) => {
    const server = net.createServer();
    server.once('error', () => resolve(false));
    server.listen(port, '0.0.0.0', () => server.close(() => resolve(true)));
  });
}

async function freePortBlock(count) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const base = await freePort();
    const ports = Array.from({ length: count }, (_, index) => base + index * 100);
    if (ports[ports.length - 1] > 65000) continue;
    const available = await Promise.all(ports.map(portAvailable));
    if (available.every(Boolean)) return base;
  }
  throw new Error('unable to allocate server port block');
}

function signToken(userId) {
  const payload = Buffer.from(JSON.stringify({
    sub: userId,
    v: 0,
    exp: Date.now() + 2 * 60 * 60 * 1000,
    k: 'desktop'
  })).toString('base64url');
  const signature = crypto.createHmac('sha256', secret).update(payload).digest('base64url');
  return `${payload}.${signature}`;
}

function account(index) {
  const id = `u_capacity_${index}`;
  return {
    id,
    username: `capacity_${index}`,
    nickname: `Capacity ${index}`,
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

function processMemoryMb(pid) {
  if (process.platform === 'win32') {
    const result = spawnSync('powershell.exe', [
      '-NoProfile',
      '-Command',
      `(Get-Process -Id ${Number(pid)} -ErrorAction Stop).WorkingSet64`
    ], { encoding: 'utf8', timeout: 5000, windowsHide: true });
    const value = Number(String(result.stdout || '').trim());
    return Number.isFinite(value) && value > 0 ? Math.round(value / 1024 / 1024) : null;
  }
  const result = spawnSync('ps', ['-o', 'rss=', '-p', String(pid)], {
    encoding: 'utf8',
    timeout: 5000
  });
  const value = Number(String(result.stdout || '').trim());
  return Number.isFinite(value) && value > 0 ? Math.round(value / 1024) : null;
}

async function waitForHealth(base, child, logs) {
  for (let attempt = 0; attempt < 300; attempt += 1) {
    if (child.exitCode !== null) {
      throw new Error(`capacity server exited:\n${logs.join('')}`);
    }
    try {
      if ((await fetch(`${base}/api/health`)).ok) return;
    } catch (_) {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error(`capacity server start timeout:\n${logs.join('')}`);
}

function openSocket(base, user, host = '127.0.0.1', sourceHost = '127.0.0.1',
                    sourcePort = 0) {
  const token = signToken(user.id);
  const parsed = new URL(base);
  const port = Number(parsed.port || 80);
  const key = crypto.randomBytes(16).toString('base64');
  const connectOptions = { host, port, localAddress: sourceHost };
  if (sourcePort > 0) connectOptions.localPort = sourcePort;
  const netSocket = net.createConnection(connectOptions);
  const connection = {
    userId: user.id,
    base,
    host,
    sourceHost,
    socket: {
      close() {
        netSocket.destroy();
      }
    },
    ready: false,
    closed: false,
    closeCode: 0,
    closeReason: '',
    received: new Set(),
    duplicateCount: 0,
    orderViolations: 0,
    lastSeq: 0,
    momentIds: new Set(),
    momentEvents: 0,
    momentDuplicateCount: 0,
    momentUnread: null,
    momentBatched: false
  };
  connection.readyPromise = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`websocket ready timeout: ${user.id}`)), 90000);
    let buffer = Buffer.alloc(0);
    let upgraded = false;

    function consumePayload(payload, opcode) {
      if (opcode === 0x8) {
        connection.closed = true;
        netSocket.end();
        return;
      }
      if (opcode === 0x9) {
        const mask = crypto.randomBytes(4);
        const frame = Buffer.alloc(6 + payload.length);
        frame[0] = 0x8a;
        frame[1] = 0x80 | payload.length;
        mask.copy(frame, 2);
        for (let index = 0; index < payload.length; index += 1) {
          frame[6 + index] = payload[index] ^ mask[index % 4];
        }
        netSocket.write(frame);
        return;
      }
      if (opcode !== 0x1) return;
      let eventPayload;
      try { eventPayload = JSON.parse(payload.toString('utf8')); } catch (_) { return; }
      if (eventPayload.type === 'ready') {
        connection.ready = true;
        clearTimeout(timer);
        resolve(connection);
      }
      if (eventPayload.type === 'message' && eventPayload.message) {
        const clientId = String(eventPayload.message.clientId || '');
        if (clientId) {
          if (connection.received.has(clientId)) {
            connection.duplicateCount += 1;
          }
          const seq = Number(eventPayload.message.seq || 0);
          if (seq > 0) {
            if (connection.lastSeq > 0 && seq < connection.lastSeq) {
              connection.orderViolations += 1;
            }
            connection.lastSeq = Math.max(connection.lastSeq, seq);
          }
          connection.received.add(clientId);
          deliverWaiter(clientId, connection, Date.now());
        }
      }
      if (eventPayload.type === 'moment'
          && ['new', 'newBatch'].includes(eventPayload.action)) {
        const momentId = String(eventPayload.moment?.id || '');
        const batchCount = eventPayload.action === 'newBatch'
          ? Math.max(1, Number(eventPayload.count) || 1)
          : 1;
        connection.momentEvents += batchCount;
        if (eventPayload.action === 'newBatch') connection.momentBatched = true;
        if (momentId && eventPayload.action === 'new') {
          if (connection.momentIds.has(momentId)) {
            connection.momentDuplicateCount += 1;
          }
          connection.momentIds.add(momentId);
        }
        const delta = Number(eventPayload.momentUnreadDelta);
        if (Number.isFinite(delta)) {
          connection.momentUnread = Math.max(0, (connection.momentUnread || 0) + delta);
        } else {
          const unread = Number(eventPayload.momentUnread ?? eventPayload.unread);
          if (Number.isFinite(unread)) connection.momentUnread = unread;
        }
      }
    }

    function consumeFrames() {
      while (buffer.length >= 2) {
        const opcode = buffer[0] & 0x0f;
        const masked = (buffer[1] & 0x80) !== 0;
        let length = buffer[1] & 0x7f;
        let offset = 2;
        if (length === 126) {
          if (buffer.length < 4) return;
          length = buffer.readUInt16BE(2);
          offset = 4;
        } else if (length === 127) {
          if (buffer.length < 10) return;
          const extended = buffer.readBigUInt64BE(2);
          if (extended > BigInt(Number.MAX_SAFE_INTEGER)) {
            netSocket.destroy();
            return;
          }
          length = Number(extended);
          offset = 10;
        }
        const maskOffset = masked ? 4 : 0;
        if (buffer.length < offset + maskOffset + length) return;
        let payload = buffer.subarray(
          offset + maskOffset,
          offset + maskOffset + length
        );
        if (masked) {
          const mask = buffer.subarray(offset, offset + 4);
          payload = Buffer.from(payload);
          for (let index = 0; index < payload.length; index += 1) {
            payload[index] ^= mask[index % 4];
          }
        }
        buffer = buffer.subarray(offset + maskOffset + length);
        consumePayload(payload, opcode);
      }
    }

    netSocket.setNoDelay(true);
    netSocket.on('connect', () => {
      netSocket.write([
        'GET /?token=' + encodeURIComponent(token) + ' HTTP/1.1',
        `Host: ${host}:${port}`,
        'Upgrade: websocket',
        'Connection: Upgrade',
        `Sec-WebSocket-Key: ${key}`,
        'Sec-WebSocket-Version: 13',
        'X-Device-Kind: desktop',
        'X-Device-Id: capacity-load',
        '',
        ''
      ].join('\r\n'));
    });
    netSocket.on('data', (chunk) => {
      buffer = buffer.length ? Buffer.concat([buffer, chunk]) : chunk;
      if (!upgraded) {
        const marker = buffer.indexOf('\r\n\r\n');
        if (marker < 0) return;
        const head = buffer.subarray(0, marker).toString('utf8');
        if (!/^HTTP\/1\.1 101\b/.test(head)) {
          clearTimeout(timer);
          reject(new Error(`websocket upgrade failed: ${user.id}: ${head.split('\r\n')[0]}`));
          netSocket.destroy();
          return;
        }
        upgraded = true;
        buffer = buffer.subarray(marker + 4);
      }
      consumeFrames();
    });
    netSocket.on('error', (error) => {
      clearTimeout(timer);
      reject(new Error(`websocket error: ${user.id}: ${error.message}`));
    });
    netSocket.on('close', () => {
      connection.closed = true;
      if (!connection.ready) {
        clearTimeout(timer);
        reject(new Error(`websocket closed before ready: ${user.id}`));
      }
    });
  });
  return connection;
}

const waiters = new Map();
const sentClientIds = new Set();

function deliverWaiter(clientId, connection, at) {
  const waiter = waiters.get(clientId);
  if (!waiter || !waiter.missing.has(connection.userId)) return;
  waiter.missing.delete(connection.userId);
  waiter.latencies.push(at - waiter.startedAt);
  if (waiter.missing.size === 0) {
    clearTimeout(waiter.timer);
    waiters.delete(clientId);
    waiter.resolve(waiter);
  }
}

function waitForDelivery(clientId, users, timeoutMs) {
  return new Promise((resolve) => {
    const waiter = {
      clientId,
      missing: new Set(users.map((user) => user.id)),
      latencies: [],
      startedAt: Date.now(),
      resolve
    };
    waiter.timer = setTimeout(() => {
      waiters.delete(clientId);
      resolve(waiter);
    }, timeoutMs);
    waiters.set(clientId, waiter);
  });
}

async function sendMessage(base, sender, clientId) {
  const response = await fetch(`${base}/api/chats/${CHAT_ID}/messages`, {
    method: 'POST',
    headers: {
      Cookie: `${TOKEN_COOKIE}=${encodeURIComponent(signToken(sender.id))}`,
      'Content-Type': 'application/json',
      'x-device-kind': 'desktop',
      'x-device-id': 'capacity-load'
    },
    body: JSON.stringify({
      kind: 'text',
      content: `capacity message ${clientId}`,
      clientId,
      mentions: []
    })
  });
  if (!response.ok) {
    throw new Error(`send failed HTTP ${response.status}: ${await response.text()}`);
  }
  return clientId;
}

async function openConnections(bases, users, target, existing, batchSize, hosts, sources) {
  let cursor = existing.length;
  while (cursor < target) {
    const batch = users.slice(cursor, Math.min(target, cursor + batchSize));
    const opened = await Promise.all(batch.map(async (user, offset) => {
      let lastError;
      for (let attempt = 0; attempt < 24; attempt += 1) {
        const globalIndex = cursor + offset;
        const sourceIndex = globalIndex % sources.length;
        const sourceSlot = Math.floor(globalIndex / sources.length);
        const sourcePort = attempt < 16
          ? 20000 + ((sourceSlot + attempt * 7919) % 35000)
          : 0;
        const connection = openSocket(
          bases[(cursor + offset) % bases.length],
          user,
          hosts[(cursor + offset) % hosts.length],
          sources[sourceIndex],
          sourcePort
        );
        try {
          await connection.readyPromise;
          return connection;
        } catch (error) {
          lastError = error;
          try { connection.socket.close(); } catch (_) {}
          if (!/EADDRINUSE|EACCES|ENOBUFS|ECONNREFUSED|handshake failed|closed before ready/.test(String(error))) {
            throw error;
          }
          await new Promise((resolve) => setTimeout(resolve, 25 * (attempt + 1)));
        }
      }
      throw lastError;
    }));
    existing.push(...opened);
    cursor += opened.length;
    process.stdout.write(`connected ${cursor}/${target}\r`);
  }
  process.stdout.write('\n');
}

async function runBroadcast(base, sender, connections, round) {
  const clientId = `capacity-${Date.now()}-${round}-${crypto.randomBytes(3).toString('hex')}`;
  sentClientIds.add(clientId);
  const delivery = waitForDelivery(
    clientId,
    connections.map((connection) => ({ id: connection.userId })),
    15000
  );
  await sendMessage(base, sender, clientId);
  const waiter = await delivery;
  return {
    clientId,
    delivered: waiter.latencies.length,
    missing: waiter.missing.size,
    p50Ms: percentile(waiter.latencies, 0.50),
    p95Ms: percentile(waiter.latencies, 0.95),
    p99Ms: percentile(waiter.latencies, 0.99),
    maxMs: waiter.latencies.length ? Math.max(...waiter.latencies) : null
  };
}

function strictDeliverySummary(connections) {
  const expectedIds = Array.from(sentClientIds);
  const expectedSet = new Set(expectedIds);
  let missing = 0;
  let duplicates = 0;
  let orderViolations = 0;
  let extra = 0;
  let inconsistentConnections = 0;
  for (const connection of connections) {
    let connectionMissing = 0;
    for (const id of expectedIds) {
      if (!connection.received.has(id)) connectionMissing += 1;
    }
    missing += connectionMissing;
    duplicates += connection.duplicateCount;
    orderViolations += connection.orderViolations;
    extra += Array.from(connection.received).filter((id) => !expectedSet.has(id)).length;
    if (connectionMissing || connection.received.size !== expectedIds.length) {
      inconsistentConnections += 1;
    }
  }
  return {
    expectedPerConnection: expectedIds.length,
    connectionsChecked: connections.length,
    missing,
    duplicates,
    orderViolations,
    extra,
    inconsistentConnections,
    pass: missing === 0 && duplicates === 0 && orderViolations === 0
      && extra === 0 && inconsistentConnections === 0
  };
}

async function auditStoredHistory(base, sender) {
  const expected = Array.from(sentClientIds);
  const url = `${base}/api/chats/${CHAT_ID}/messages`
    + `?limit=${Math.max(100, expected.length + 20)}&all=1`;
  const response = await fetch(url, {
    headers: {
      Cookie: `${TOKEN_COOKIE}=${encodeURIComponent(signToken(sender.id))}`,
      'x-device-kind': 'desktop',
      'x-device-id': 'capacity-audit'
    }
  });
  if (!response.ok) {
    return { pass: false, error: `history HTTP ${response.status}` };
  }
  const payload = await response.json();
  const rows = Array.isArray(payload?.data?.messages) ? payload.data.messages : [];
  const ids = new Set();
  const clientIds = new Set();
  let idDuplicates = 0;
  let clientIdDuplicates = 0;
  let orderViolations = 0;
  let lastSeq = 0;
  for (const row of rows) {
    const id = String(row.id || '');
    const clientId = String(row.clientId || '');
    const seq = Number(row.seq || 0);
    if (ids.has(id)) idDuplicates += 1;
    ids.add(id);
    if (clientId) {
      if (clientIds.has(clientId)) clientIdDuplicates += 1;
      clientIds.add(clientId);
    }
    if (seq > 0) {
      if (lastSeq > 0 && seq < lastSeq) orderViolations += 1;
      lastSeq = Math.max(lastSeq, seq);
    }
  }
  const missing = expected.filter((id) => !clientIds.has(id)).length;
  return {
    rows: rows.length,
    expected: expected.length,
    missing,
    idDuplicates,
    clientIdDuplicates,
    orderViolations,
    pass: missing === 0 && idDuplicates === 0
      && clientIdDuplicates === 0 && orderViolations === 0
  };
}

async function createMoment(base, author, index) {
  const response = await fetch(`${base}/api/moments`, {
    method: 'POST',
    headers: {
      Cookie: `${TOKEN_COOKIE}=${encodeURIComponent(signToken(author.id))}`,
      'Content-Type': 'application/json',
      'x-device-kind': 'desktop',
      'x-device-id': 'moment-storm'
    },
    body: JSON.stringify({
      content: `moment storm ${index}`,
      images: []
    })
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(`moment create failed HTTP ${response.status}: ${JSON.stringify(payload)}`);
  }
  return String(payload?.data?.moment?.id || '');
}

async function runMomentStorm(base, authors, viewers, count, concurrency, auditUser,
                              dataDir) {
  const startedAt = Date.now();
  const createStartedAt = Date.now();
  const ids = [];
  for (let start = 0; start < count; start += concurrency) {
    const end = Math.min(count, start + concurrency);
    const batch = await Promise.all(
      Array.from({ length: end - start }, (_, offset) =>
        createMoment(base, authors[(start + offset) % authors.length], start + offset)
      )
    );
    ids.push(...batch.filter(Boolean));
  }
  const createDurationMs = Date.now() - createStartedAt;
  const created = new Set(ids);
  const deliveryStartedAt = Date.now();
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline
         && viewers.some((connection) => (connection.momentUnread || 0) < created.size)) {
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  const deliveryDurationMs = Date.now() - deliveryStartedAt;
  let missing = 0;
  let duplicates = 0;
  let extra = 0;
  let unreadMismatch = 0;
  let eventCountMismatch = 0;
  for (const connection of viewers) {
    if (!connection.momentBatched) {
      for (const id of created) {
        if (!connection.momentIds.has(id)) missing += 1;
      }
      extra += Array.from(connection.momentIds).filter((id) => !created.has(id)).length;
    }
    duplicates += connection.momentDuplicateCount;
    if (connection.momentUnread !== created.size) unreadMismatch += 1;
    if (connection.momentEvents !== created.size) eventCountMismatch += 1;
  }
  const auditStartedAt = Date.now();
  const feedIds = new Set();
  try {
    const base = JSON.parse(fs.readFileSync(path.join(dataDir, 'moments.json'), 'utf8'));
    (Array.isArray(base.moments) ? base.moments : []).forEach((row) => {
      if (row && row.id) feedIds.add(String(row.id));
    });
  } catch (_) {}
  try {
    const lines = fs.readFileSync(path.join(dataDir, 'moments-log.jsonl'), 'utf8')
      .split('\n');
    lines.forEach((line) => {
      if (!line.trim()) return;
      try {
        const record = JSON.parse(line);
        if (record.op === 'delete') feedIds.delete(String(record.id || ''));
        else if (record.moment && record.moment.id) {
          feedIds.add(String(record.moment.id));
        }
      } catch (_) {}
    });
  } catch (_) {}
  const storedMissing = Array.from(created).filter((id) => !feedIds.has(id)).length;
  const auditDurationMs = Date.now() - auditStartedAt;
  return {
    mode: 'moment-instant-peak',
    viewers: viewers.length,
    moments: created.size,
    expectedDeliveries: viewers.length * created.size,
    deliveredUnique: viewers.reduce((sum, connection) => sum + connection.momentIds.size, 0),
    missing,
    duplicates,
    extra,
    unreadMismatch,
    eventCountMismatch,
    storedMissing,
    durationMs: Date.now() - startedAt,
    createDurationMs,
    deliveryDurationMs,
    auditDurationMs,
    pass: missing === 0 && duplicates === 0 && extra === 0
      && unreadMismatch === 0 && eventCountMismatch === 0 && storedMissing === 0
  };
}

async function runWorker() {
  const base = String(process.env.CAPACITY_LOAD_BASE || '');
  const bases = String(process.env.CAPACITY_LOAD_BASES || base)
    .split(',')
    .filter(Boolean);
  const start = Math.max(0, Number(process.env.CAPACITY_LOAD_START) || 0);
  const count = Math.max(1, Number(process.env.CAPACITY_LOAD_COUNT) || 1);
  const batch = Math.max(1, Number(process.env.CAPACITY_LOAD_BATCH) || 200);
  const hosts = String(process.env.CAPACITY_LOAD_TARGETS || '127.0.0.1')
    .split(',')
    .filter(Boolean);
  const sources = String(process.env.CAPACITY_LOAD_SOURCES || '127.0.0.1')
    .split(',')
    .filter(Boolean);
  if (!base || typeof process.send !== 'function') {
    throw new Error('capacity worker requires an IPC parent and base URL');
  }
  const users = Array.from({ length: count }, (_, index) => account(start + index));
  const connections = [];
  try {
    await openConnections(bases, users, count, connections, batch, hosts, sources);
    process.send({ type: 'ready', count, pid: process.pid });
    process.on('message', async (message) => {
      if (!message || message.type !== 'expect') return;
      process.send({ type: 'expecting', clientId: message.clientId });
      const waiter = await waitForDelivery(
        message.clientId,
        users,
        Math.max(1000, Number(message.timeoutMs) || 30000)
      );
      process.send({
        type: 'delivered',
        clientId: message.clientId,
        delivered: waiter.latencies.length,
        missing: waiter.missing.size,
        p99Ms: percentile(waiter.latencies, 0.99),
        maxMs: waiter.latencies.length ? Math.max(...waiter.latencies) : null
      });
    });
    process.on('SIGTERM', () => {
      connections.forEach((connection) => {
        try { connection.socket.close(); } catch (_) {}
      });
    });
  } catch (error) {
    process.send({ type: 'error', error: String(error && error.stack || error) });
    throw error;
  }
}

function waitForChildMessage(record, predicate, timeoutMs, pending) {
  return new Promise((resolve, reject) => {
    const cached = record.messages.findIndex(predicate);
    if (cached >= 0) {
      const [message] = record.messages.splice(cached, 1);
      resolve(message);
      return;
    }
    const key = Symbol('waiter');
    pending.set(key, { record, predicate, resolve, reject });
    const timer = setTimeout(() => {
      pending.delete(key);
      reject(new Error(`worker ${record.worker.pid} message timeout`));
    }, timeoutMs);
    const resolver = pending.get(key);
    resolver.resolve = (message) => {
      clearTimeout(timer);
      pending.delete(key);
      resolve(message);
    };
  });
}

async function runDistributed(base, users, child, workerCount, rounds) {
  const totalConnections = users.length;
  const perWorker = Math.ceil(totalConnections / workerCount);
  const workers = [];
  const pending = new Map();
  try {
    for (let index = 0; index < workerCount; index += 1) {
      const start = index * perWorker;
      const count = Math.min(perWorker, totalConnections - start);
      if (count <= 0) continue;
      const worker = require('child_process').fork(__filename, [], {
        env: Object.assign({}, process.env, {
          CAPACITY_LOAD_WORKER: '1',
          CAPACITY_LOAD_SECRET: secret,
          CAPACITY_LOAD_BASE: base,
          CAPACITY_LOAD_START: String(start),
          CAPACITY_LOAD_COUNT: String(count),
          CAPACITY_LOAD_BATCH: String(
            Math.max(25, Math.min(200, Number(arg('batch', '100'))))
          ),
          CAPACITY_LOAD_TARGETS: String(arg('targets', '127.0.0.1')),
          CAPACITY_LOAD_SOURCES: String(arg('sources', '127.0.0.1'))
        }),
        stdio: ['ignore', 'inherit', 'inherit', 'ipc']
      });
      const record = { worker, count, messages: [] };
      worker.on('message', (message) => {
        if (!message) return;
        if (message.type === 'error') {
          for (const [key, waiter] of pending.entries()) {
            if (waiter.record !== record) continue;
            waiter.reject(new Error(message.error || 'capacity worker failed'));
            pending.delete(key);
          }
          return;
        }
        for (const [key, waiter] of pending.entries()) {
          if (waiter.record === record && waiter.predicate(message)) {
            waiter.resolve(message);
            pending.delete(key);
            return;
          }
        }
        record.messages.push(message);
        if (record.messages.length > 200) record.messages.shift();
      });
      workers.push(record);
    }
    const ready = await Promise.all(workers.map((record) =>
      waitForChildMessage(record, (message) => message.type === 'ready', 180000, pending)
    ));
    const connected = ready.reduce((sum, row) => sum + Number(row.count || 0), 0);
    const memoryBefore = processMemoryMb(child.pid);
    const results = [];
    for (let round = 0; round < rounds; round += 1) {
      const clientId = `capacity-distributed-${Date.now()}-${round}-${crypto.randomBytes(3).toString('hex')}`;
      const expecting = workers.map((record) =>
        waitForChildMessage(
          record,
          (message) => message.type === 'expecting' && message.clientId === clientId,
          10000,
          pending
        )
      );
      workers.forEach(({ worker }) => worker.send({
        type: 'expect',
        clientId,
        timeoutMs: 30000
      }));
      await Promise.all(expecting);
      await sendMessage(base, users[0], clientId);
      const delivered = await Promise.all(workers.map((record) =>
        waitForChildMessage(
          record,
          (message) => message.type === 'delivered' && message.clientId === clientId,
          35000,
          pending
        )
      ));
      const totalDelivered = delivered.reduce((sum, row) => sum + Number(row.delivered || 0), 0);
      const p99 = Math.max(...delivered.map((row) => Number(row.p99Ms) || 35000));
      results.push({
        clientId,
        expected: connected,
        delivered: totalDelivered,
        deliveryRate: connected ? Number((totalDelivered / connected).toFixed(6)) : 0,
        p99Ms: p99,
        pass: totalDelivered === connected && p99 <= 5000
      });
    }
    const result = {
      isolated: true,
      mode: 'distributed-clients',
      connections: connected,
      workerCount: workers.length,
      rounds,
      storm: results,
      serverMemoryBeforeMb: memoryBefore,
      serverMemoryAfterMb: processMemoryMb(child.pid),
      pass: results.every((row) => row.pass)
    };
    console.log(JSON.stringify(result, null, 2));
    if (!result.pass) process.exitCode = 2;
  } finally {
    workers.forEach(({ worker }) => {
      try { worker.send({ type: 'stop' }); } catch (_) {}
      try { worker.kill(); } catch (_) {}
    });
  }
}

async function main() {
  const stages = String(arg('stages', '100,500,1000'))
    .split(',')
    .map(Number)
    .filter((value) => Number.isInteger(value) && value > 0)
    .sort((a, b) => a - b);
  const maxConnections = Math.max(...stages);
  const rounds = Math.max(1, Number(arg('rounds', '3')));
  const connectionBatch = Math.max(1, Math.min(1000, Number(arg('batch', '200'))));
  const workerCount = Math.max(0, Number(arg('workers', '0')));
  const serverCount = Math.max(1, Math.min(8, Number(arg('servers', '1'))));
  const momentStorm = Math.max(0, Number(arg('moments', '0')));
  const momentConcurrency = Math.max(1, Number(arg('moment-concurrency', '100')));
  const momentAuthors = Math.max(0, Number(arg('moment-authors', '0')));
  const targetHosts = String(arg('targets', '127.0.0.1'))
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);
  const sourceHosts = String(arg('sources', '127.0.0.1'))
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);
  const reconnectFraction = Math.min(0.2, Math.max(0, Number(arg('reconnect', '0.1'))));
  const holdMs = Math.max(0, Number(arg('hold-ms', '0')));
  const holdSampleMs = Math.max(1000, Number(arg('hold-sample-ms', '30000')));
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-capacity-load-'));
  const serverBasePort = serverCount > 1
    ? await freePortBlock(serverCount)
    : await freePort();
  const serverPorts = Array.from(
    { length: serverCount },
    (_, index) => serverBasePort + index * 100
  );
  const bases = serverPorts.map((port) => `http://127.0.0.1:${port}`);
  const base = bases[0];
  const logs = [];
  activeLogs = logs;
  const users = Array.from({ length: maxConnections }, (_, index) => account(index));
  const connections = [];
  const children = [];

  try {
    fs.mkdirSync(path.join(dataDir, 'messages'), { recursive: true });
    fs.writeFileSync(path.join(dataDir, 'secret.key'), secret, 'utf8');
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({ users }), 'utf8');
    fs.writeFileSync(path.join(dataDir, 'friendships.json'), JSON.stringify({
      friendships: momentStorm > 0
        ? (momentAuthors > 0
          ? users.slice(1, 1 + momentAuthors).map((user, index) => ({
            id: `capacity-friend-${index}`,
            fromId: user.id,
            toId: users[0].id,
            status: 'accepted',
            createdAt: '2026-01-01T00:00:00.000Z'
          }))
          : users.slice(1).map((user, index) => ({
            id: `capacity-friend-${index}`,
            fromId: users[0].id,
            toId: user.id,
            status: 'accepted',
            createdAt: '2026-01-01T00:00:00.000Z'
          })))
        : []
    }), 'utf8');
    fs.writeFileSync(path.join(dataDir, 'chats.json'), JSON.stringify({
      chats: [{
        id: CHAT_ID,
        type: 'group',
        name: `${maxConnections} capacity load`,
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
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({
      sliderLogin: 0
    }), 'utf8');
    fs.writeFileSync(path.join(dataDir, 'risk-config.json'), JSON.stringify({
      enabled: false
    }), 'utf8');
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({
      multiDevice: 1
    }), 'utf8');
    fs.writeFileSync(path.join(dataDir, 'im.json'), JSON.stringify({
      allowStranger: true,
      maxGroupMembers: Math.max(10000, maxConnections)
    }), 'utf8');

    for (let serverId = 0; serverId < serverCount; serverId += 1) {
      const child = spawn(process.execPath, ['server.js'], {
        cwd: SERVER_DIR,
        env: Object.assign({}, process.env, {
          DATA_DIR: dataDir,
          PORT: String(serverPorts[serverId]),
          HOST: targetHosts.length > 1 ? '0.0.0.0' : '127.0.0.1',
          TURN_PORT: String(await freePort()),
          CHRIS_LOCAL_ONLY: '1',
          ALLOW_PLAIN_WS: '1',
          AML_RUNTIME_ENABLED: '0',
          DISABLE_STARTUP_BOT_BACKFILL: '1',
          MESSAGE_RELIABILITY_ENABLED: '1',
          SHARD_COUNT: String(serverCount),
          SHARD_BASE_PORT: String(serverBasePort),
          SHARD_RUNTIME_BASE_PORT: String(serverBasePort),
          SHARD_ID: String(serverId),
          // Isolated load harness only. Production keeps its normal limits.
          WS_MAX_PER_IP: String(maxConnections + 1000),
          WS_NEW_PER_SEC: String(maxConnections + 1000),
          API_MAX_PER_WINDOW: String(Math.max(1_000_000, maxConnections * 1000)),
          MSG_MAX_PER_WINDOW: String(Math.max(1_000_000, maxConnections * 1000)),
          GLOBAL_MSG_PER_SEC: '1000000',
          MOMENT_MAX_PER_MINUTE: '1000000',
          MOMENT_MAX_PER_DAY: '1000000'
        }),
        stdio: ['ignore', 'pipe', 'pipe'],
        windowsHide: true
      });
      child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
      child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
      children.push(child);
    }
    await Promise.all(children.map((child, index) =>
      waitForHealth(bases[index], child, logs)
    ));
    const child = children[0];
    if (momentStorm > 0) {
      const inboxPeak = momentAuthors > 0;
      const authors = inboxPeak
        ? users.slice(1, 1 + momentAuthors)
        : [users[0]];
      const viewers = inboxPeak ? [users[0]] : users.slice(1);
      await openConnections(
        bases,
        viewers,
        viewers.length,
        connections,
        connectionBatch,
        targetHosts,
        sourceHosts
      );
      await new Promise((resolve) => setTimeout(resolve, 800));
      const result = await runMomentStorm(
        base,
        authors,
        connections,
        momentStorm,
        momentConcurrency,
        users[0],
        dataDir
      );
      console.log(JSON.stringify({
        isolated: true,
        serverCount,
        serverMemoryMb: processMemoryMb(child.pid),
        ...result
      }, null, 2));
      if (!result.pass) process.exitCode = 2;
      return;
    }
    if (workerCount > 1) {
      await runDistributed(
        base,
        users,
        child,
        workerCount,
        Math.max(1, Number(arg('rounds', '3')))
      );
      return;
    }

    const results = [];
    for (const target of stages) {
      const startedAt = Date.now();
      await openConnections(
        bases,
        users,
        target,
        connections,
        connectionBatch,
        targetHosts,
        sourceHosts
      );
      await new Promise((resolve) => setTimeout(resolve, serverCount > 1 ? 1600 : 500));
      const active = connections.filter((connection) =>
        connection.ready && !connection.closed
      );
      if (holdMs > 0) {
        const holdStartedAt = Date.now();
        let minActive = active.length;
        let maxClosed = 0;
        let maxMemoryMb = processMemoryMb(child.pid);
        const samples = [];
        while (Date.now() - holdStartedAt < holdMs) {
          await new Promise((resolve) =>
            setTimeout(resolve, Math.min(holdSampleMs,
              holdMs - (Date.now() - holdStartedAt)))
          );
          const alive = connections.filter((connection) =>
            connection.ready && !connection.closed
          ).length;
          const closed = connections.length - alive;
          const memoryMb = processMemoryMb(child.pid);
          minActive = Math.min(minActive, alive);
          maxClosed = Math.max(maxClosed, closed);
          if (memoryMb != null) maxMemoryMb = Math.max(maxMemoryMb || 0, memoryMb);
          samples.push({
            atMs: Date.now() - holdStartedAt,
            alive,
            closed,
            memoryMb
          });
        }
        const soak = {
          durationMs: Date.now() - holdStartedAt,
          connections: target,
          minActive,
          maxClosed,
          maxMemoryMb,
          samples,
          pass: minActive === target && maxClosed === 0
        };
        console.log(JSON.stringify({ type: 'long-connection-soak', ...soak }));
        if (!soak.pass) throw new Error('long-connection soak failed: '
          + JSON.stringify(soak));
      }
      active.forEach((connection) => {
        connection.received.clear();
        connection.duplicateCount = 0;
        connection.orderViolations = 0;
        connection.lastSeq = 0;
      });
      sentClientIds.clear();
      const memoryBefore = processMemoryMb(child.pid);
      const broadcasts = [];
      for (let round = 0; round < rounds; round += 1) {
        broadcasts.push(await runBroadcast(base, users[0], active, round));
      }

      const reconnectCount = Math.max(0, Math.round(active.length * reconnectFraction));
      if (reconnectCount > 0) {
        const reconnecting = active.slice(0, reconnectCount);
        reconnecting.forEach((connection) => connection.socket.close());
        await new Promise((resolve) => setTimeout(resolve, 250));
        const replacements = reconnecting.map((connection) => {
          const user = users.find((row) => row.id === connection.userId);
          return openSocket(connection.base, user, connection.host, connection.sourceHost);
        });
        await Promise.all(replacements.map((connection) => connection.readyPromise));
        for (let index = 0; index < active.length; index += 1) {
          if (active[index].closed) active[index] = replacements.shift();
        }
      }
      const reconnectBroadcast = await runBroadcast(base, users[0], active, 99);
      const strict = reconnectCount === 0 ? strictDeliverySummary(active) : null;
      const stored = reconnectCount === 0
        ? await auditStoredHistory(base, users[0])
        : null;
      const expected = active.length * (rounds + 1);
      const delivered = broadcasts.reduce((sum, row) => sum + row.delivered, 0)
        + reconnectBroadcast.delivered;
      const p99s = broadcasts.map((row) => row.p99Ms || 15000)
        .concat([reconnectBroadcast.p99Ms || 15000]);
      const stage = {
        connections: active.length,
        closedConnections: connections.filter((connection) => connection.closed)
          .slice(0, 20)
          .map((connection) => ({
            userId: connection.userId,
            code: connection.closeCode,
            reason: connection.closeReason
          })),
        connectDurationMs: Date.now() - startedAt,
        rounds: rounds + 1,
        reconnectCount,
        expectedDeliveries: expected,
        delivered,
        deliveryRate: expected ? Number((delivered / expected).toFixed(6)) : 0,
        p99Ms: Math.max(...p99s),
        broadcasts,
        reconnectBroadcast,
        strict,
        stored,
        serverMemoryBeforeMb: memoryBefore,
        serverMemoryAfterMb: processMemoryMb(child.pid)
      };
      stage.pass = stage.deliveryRate >= 0.999 && stage.p99Ms <= 2000
        && stage.connections === target && (!strict || strict.pass)
        && (!stored || stored.pass);
      results.push(stage);
      console.log(JSON.stringify(stage));
      if (!stage.pass) break;
    }

    const passed = results.length === stages.length && results.every((row) => row.pass);
    console.log(JSON.stringify({
      isolated: true,
      dataDir,
      serverCount,
      stages,
      passed,
      results
    }, null, 2));
    if (!passed) process.exitCode = 2;
  } finally {
    connections.forEach((connection) => {
      try { connection.socket.close(); } catch (_) {}
    });
    children.forEach((child) => {
      if (child && child.exitCode === null) child.kill();
    });
    await new Promise((resolve) => setTimeout(resolve, 250));
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

const entry = process.env.CAPACITY_LOAD_WORKER === '1' ? runWorker : main;
entry().catch((error) => {
  console.error(error.stack || error);
  if (activeLogs.length) {
    console.error('--- isolated server log tail ---');
    console.error(activeLogs.join('').split('\n').slice(-120).join('\n'));
  }
  process.exitCode = 1;
});
