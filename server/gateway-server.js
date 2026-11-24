'use strict';

/**
 * Optional independent WebSocket gateway.
 *
 * The gateway keeps client-side raw WebSocket frames in a multiplexed upstream
 * envelope. It is intentionally opt-in: existing clients keep using server.js
 * until the gateway fleet and directory are deployed.
 */

const http = require('http');
const crypto = require('crypto');
const ws = require('./lib/ws');
const { ConnectionGovernor } = require('./lib/connection-governor');
const { envelope, decodeEnvelope } = require('./lib/gateway-multiplex');
const { SessionCell } = require('./lib/session-cell');

const PORT = Number(process.env.GATEWAY_PORT || 5290);
const HOST = process.env.GATEWAY_HOST || '0.0.0.0';
const UPSTREAM = process.env.GATEWAY_UPSTREAM_WS
  || 'ws://127.0.0.1:5180/__gateway/upstream';
const BACKEND = String(process.env.GATEWAY_BACKEND_HTTP || 'http://127.0.0.1:5180')
  .replace(/\/+$/, '');
const SECRET = String(process.env.GATEWAY_ADMIN_SECRET || '');
const NODE_ID = String(process.env.GATEWAY_NODE_ID || `gateway-${PORT}`);
const governor = new ConnectionGovernor({
  maxTotal: Number(process.env.WS_MAX_TOTAL_CONNECTIONS) || 100000,
  maxPerUser: Number(process.env.WS_MAX_CONNECTIONS_PER_USER) || 4,
  maxPerIp: Number(process.env.WS_MAX_CONNECTIONS_PER_IP) || 120,
  softLoadRatio: Number(process.env.WS_SOFT_LOAD_RATIO) || 0.85
});
const sessions = new SessionCell({
  maxConnections: Number(process.env.GATEWAY_SESSION_CAPACITY) || 100000
});
let upstream = null;
let upstreamReady = false;
let reconnectTimer = null;
let heartbeatTimer = null;
let nextPublishId = 0;
const MAX_CLIENT_QUEUE_BYTES = Number(process.env.GATEWAY_MAX_QUEUE_BYTES) || 512 * 1024;

function log(message) {
  console.log(`[gateway ${NODE_ID}] ${message}`);
}

function jsonPost(path, body) {
  if (!SECRET) return Promise.resolve(null);
  return fetch(BACKEND + path, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-gateway-admin-secret': SECRET
    },
    body: JSON.stringify(body || {}),
    signal: AbortSignal.timeout(2500)
  }).then((response) => response.ok ? response.json() : null).catch(() => null);
}

function connectUpstream() {
  if (upstream && (upstream.readyState === WebSocket.OPEN
      || upstream.readyState === WebSocket.CONNECTING)) return;
  const url = new URL(UPSTREAM);
  if (SECRET) url.searchParams.set('secret', SECRET);
  upstream = new WebSocket(url.toString());
  upstream.onopen = () => {
    upstreamReady = true;
    log('upstream connected');
    jsonPost('/__gateway/nodes', {
      id: NODE_ID,
      endpoint: `http://${HOST === '0.0.0.0' ? '127.0.0.1' : HOST}:${PORT}`,
      cellId: process.env.GATEWAY_CELL_ID || '',
      failureDomain: process.env.GATEWAY_FAILURE_DOMAIN || '',
      capacity: governor.maxTotal,
      connections: governor.total
    });
    for (const client of sessions.all()) {
      openClientOnUpstream(client);
      flushClientData(client);
    }
  };
  upstream.onmessage = (event) => {
    const message = decodeEnvelope(event.data);
    if (!message) return;
    const client = sessions.get(message.connectionId);
    if (!client) return;
    if (message.type === 'open-ok') {
      client.userId = String(message.userId || '');
      client.reopened = true;
      return;
    }
    if (message.type === 'data' && message.data) {
      try { client.socket.write(Buffer.from(String(message.data), 'base64')); }
      catch (_) { client.socket.destroy(); }
      return;
    }
    if (message.type === 'closed') client.socket.end();
  };
  upstream.onerror = () => {
    log('upstream error');
  };
  upstream.onclose = () => {
    upstreamReady = false;
    upstream = null;
    /* Keep client TCP/WebSocket connections alive. Re-open virtual sessions
       after the next upstream connection and flush bounded pending bytes. */
    if (!reconnectTimer) {
      reconnectTimer = setTimeout(() => {
        reconnectTimer = null;
        connectUpstream();
      }, 1000);
      if (reconnectTimer.unref) reconnectTimer.unref();
    }
  };
}

function openClientOnUpstream(client) {
  if (!client || !client.open) return false;
  return send('open', client.connectionId, client.open);
}

function queueClientData(client, chunk) {
  if (!client) return false;
  client.pendingBytes = Number(client.pendingBytes) || 0;
  if (client.pendingBytes + chunk.length > MAX_CLIENT_QUEUE_BYTES) return false;
  client.pending.push(chunk);
  client.pendingBytes += chunk.length;
  return true;
}

function flushClientData(client) {
  if (!client) return;
  while (client.pending.length) {
    const chunk = client.pending.shift();
    client.pendingBytes -= chunk.length;
    if (!send('data', client.connectionId, {
      data: chunk.toString('base64')
    })) {
      client.pending.unshift(chunk);
      client.pendingBytes += chunk.length;
      return;
    }
  }
}

function send(type, connectionId, payload) {
  if (!upstream || upstream.readyState !== WebSocket.OPEN) return false;
  try {
    upstream.send(envelope(type, connectionId, payload));
    return true;
  } catch (_) {
    return false;
  }
}

function reject(socket, status, reason) {
  const text = reason || 'Gateway unavailable';
  socket.end(
    `HTTP/1.1 ${status} ${text}\r\n` +
    `Retry-After: 1\r\nContent-Length: 0\r\nConnection: close\r\n\r\n`
  );
}

function requestIp(req) {
  return String((req.socket && req.socket.remoteAddress) || '')
    .replace('::ffff:', '').replace('::1', '127.0.0.1');
}

function readJsonBody(req) {
  return new Promise((resolve, rejectBody) => {
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > 2 * 1024 * 1024) {
        rejectBody(new Error('body too large'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      try {
        const raw = Buffer.concat(chunks).toString('utf8');
        resolve(raw ? JSON.parse(raw) : {});
      } catch (error) {
        rejectBody(error);
      }
    });
    req.on('error', rejectBody);
  });
}

function internalAuthorized(req) {
  if (!SECRET) return false;
  const supplied = String(req.headers['x-gateway-admin-secret'] || '');
  const a = Buffer.from(supplied);
  const b = Buffer.from(SECRET);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

const server = http.createServer(async (req, res) => {
  if (req.url === '/health' || req.url === '/__gateway/health') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({
      ok: true,
      nodeId: NODE_ID,
      upstreamReady,
      clients: sessions.size,
      governor: governor.snapshot(),
      sessionCell: sessions.snapshot()
    }));
    return;
  }
  if (req.url === '/__gateway/publish' && req.method === 'POST') {
    if (!internalAuthorized(req)) {
      res.writeHead(403, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ ok: false, error: 'forbidden' }));
      return;
    }
    try {
      const body = await readJsonBody(req);
      const wanted = new Set((body.userIds || []).map((value) => String(value)));
      const text = JSON.stringify(body.payload || {});
      let delivered = 0;
      let wouldDeliver = 0;
      for (const client of sessions.all()) {
        if (!client.userId || !wanted.has(client.userId)) continue;
        wouldDeliver += 1;
        if (body.dryRun !== true && ws.sendText(client.socket, text)) delivered += 1;
      }
      nextPublishId += 1;
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({
        ok: true,
        publishId: String(body.publishId || nextPublishId),
        delivered,
        wouldDeliver
      }));
    } catch (error) {
      res.writeHead(400, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ ok: false, error: String(error && error.message || error) }));
    }
    return;
  }
  res.writeHead(404);
  res.end();
});

server.on('upgrade', (req, socket) => {
  const key = req.headers['sec-websocket-key'];
  if (!key || String(req.headers.upgrade || '').toLowerCase() !== 'websocket') {
    socket.end('HTTP/1.1 400 Bad Request\r\n\r\n');
    return;
  }
  if (!upstreamReady || governor.draining) {
    reject(socket, 503, governor.draining ? 'Gateway draining' : 'Gateway not ready');
    return;
  }
  const ip = requestIp(req);
  const preauth = governor.admit({
    userId: 'preauth:' + ip,
    ip,
    kind: 'gateway'
  });
  if (!preauth.ok) {
    reject(socket, preauth.reason === 'draining' || preauth.reason === 'capacity' ? 503 : 429,
      'Gateway capacity');
    return;
  }
  const connectionId = crypto.randomUUID();
  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
    'Upgrade: websocket\r\nConnection: Upgrade\r\n' +
    `Sec-WebSocket-Accept: ${ws.acceptKey(key)}\r\n\r\n`
  );
  socket.setNoDelay(true);
  const client = {
    connectionId,
    socket,
    userId: '',
    pending: [],
    pendingBytes: 0,
    open: {
      nodeId: NODE_ID,
      url: req.url,
      ip,
      headers: {
        cookie: String(req.headers.cookie || ''),
        'user-agent': String(req.headers['user-agent'] || ''),
        'x-device-id': String(req.headers['x-device-id'] || ''),
        'x-device-kind': String(req.headers['x-device-kind'] || ''),
        'x-app-build': String(req.headers['x-app-build'] || '')
      }
    }
  };
  const opened = sessions.open(connectionId, client);
  if (!opened.ok) {
    governor.release(preauth.lease);
    socket.end();
    return;
  }
  socket.on('data', (chunk) => {
    if (upstreamReady && send('data', connectionId, {
      data: chunk.toString('base64')
    })) return;
    if (!queueClientData(client, chunk)) {
      socket.destroy();
    }
  });
  socket.on('close', () => {
    sessions.close(connectionId);
    governor.release(preauth.lease);
    if (upstreamReady) send('closed', connectionId, {});
  });
  openClientOnUpstream(client);
});

connectUpstream();
heartbeatTimer = setInterval(() => {
  jsonPost('/__gateway/heartbeat', {
    id: NODE_ID,
    connections: sessions.size,
    capacity: governor.maxTotal,
    draining: governor.draining
  });
}, 10000);
if (heartbeatTimer.unref) heartbeatTimer.unref();

server.listen(PORT, HOST, () => {
  log(`listening on ${HOST}:${PORT}`);
});

process.on('SIGTERM', () => {
  governor.drain();
  server.close();
  if (upstream) upstream.close();
  process.exit(0);
});
