#!/usr/bin/env node
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const http = require('http');
const https = require('https');
const { isMediaObjectPath } = require('../lib/media-object-routing');

const PORT = Number(process.env.TLS_PORT || 5443);
const CERT = process.env.TLS_CERT || '/opt/chris/tls/u.crt';
const KEY = process.env.TLS_KEY || '/opt/chris/tls/u.key';
const SHARDS = Math.max(1, Number(process.env.SHARD_COUNT || 7));
let OWNER_PORTS = String(process.env.SHARD_OWNER_PORTS || '')
  .split(',').map((value) => Number(value.trim()));
let OWNER_TARGETS = [];
const GATEWAY_ROUTING_FILE = String(process.env.GATEWAY_ROUTING_FILE || '');
const ROUTE_PLAN_FILE = String(process.env.ROUTE_PLAN_FILE || '');
const ROUTE_PLAN_FILE_SHA256 = String(process.env.ROUTE_PLAN_FILE_SHA256 || '').toLowerCase();
const USER_DIRECTORY_FILE = String(process.env.USER_DIRECTORY_FILE || '');
const PAYMENT_FAIL_CLOSED = process.env.PAYMENT_FAIL_CLOSED !== '0';
const PAYMENT_UPSTREAM_PORT = Number(process.env.PAYMENT_UPSTREAM_PORT || 0);

function validOwnerPorts(ports) {
  return Array.isArray(ports)
    && ports.length === SHARDS
    && ports.every((port) => Number.isInteger(port) && port > 0 && port <= 65535);
}

function ownerTarget(value) {
  const url = new URL(String(value || ''));
  if (!['http:', 'https:'].includes(url.protocol)
      || !url.hostname || !url.port || url.pathname !== '/'
      || url.username || url.password || url.search || url.hash) {
    throw new Error('invalid owner target: ' + value);
  }
  return {
    protocol: url.protocol,
    hostname: url.hostname,
    port: Number(url.port),
    origin: url.origin
  };
}

function applyOwnerRouting(ownerPorts, ownerTargets) {
  const targets = Array.isArray(ownerTargets) && ownerTargets.length
    ? ownerTargets.map(ownerTarget)
    : ownerPorts.map((port) => ownerTarget('http://127.0.0.1:' + port));
  if (targets.length !== SHARDS) {
    throw new Error('owner targets must contain one valid target per shard');
  }
  OWNER_PORTS = ownerPorts.slice();
  OWNER_TARGETS = targets;
}

if (!validOwnerPorts(OWNER_PORTS)) {
  throw new Error('SHARD_OWNER_PORTS must contain one valid port per shard');
}
applyOwnerRouting(
  OWNER_PORTS,
  String(process.env.SHARD_OWNER_TARGETS || '')
    .split(',').map((value) => value.trim()).filter(Boolean)
);

function routeHash(value) {
  let hash = 2166136261;
  const text = String(value || '');
  for (let index = 0; index < text.length; index += 1) {
    hash ^= text.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

let routePlan = null;
if (ROUTE_PLAN_FILE) {
  const raw = fs.readFileSync(ROUTE_PLAN_FILE);
  if (!/^[a-f0-9]{64}$/.test(ROUTE_PLAN_FILE_SHA256)
      || crypto.createHash('sha256').update(raw).digest('hex') !== ROUTE_PLAN_FILE_SHA256) {
    throw new Error('route plan file hash mismatch');
  }
  routePlan = JSON.parse(raw.toString('utf8'));
  if (!routePlan || routePlan.version !== 1 || routePlan.algorithm !== 'fnv1a32'
      || Number(routePlan.shardCount) !== SHARDS || !routePlan.assignments) {
    throw new Error('invalid route plan');
  }
}

function reloadGatewayRouting() {
  if (!GATEWAY_ROUTING_FILE) return false;
  const raw = fs.readFileSync(GATEWAY_ROUTING_FILE);
  const next = JSON.parse(raw.toString('utf8'));
  if (!next || next.version !== 1 || !validOwnerPorts(next.ownerPorts)) {
    throw new Error('invalid gateway routing update');
  }
  if (routePlan && next.routePlanHash
      && String(next.routePlanHash) !== String(routePlan.hash)) {
    throw new Error('gateway routing route-plan hash mismatch');
  }
  applyOwnerRouting(next.ownerPorts, next.ownerTargets);
  console.log(JSON.stringify({
    service: 'dual-cell-tls-proxy',
    event: 'routing-reloaded',
    ownerPorts: OWNER_PORTS,
    routePlanHash: routePlan ? routePlan.hash : ''
  }));
  return true;
}

if (GATEWAY_ROUTING_FILE && fs.existsSync(GATEWAY_ROUTING_FILE)) {
  reloadGatewayRouting();
}

let userDirectory = null;
if (USER_DIRECTORY_FILE && fs.existsSync(USER_DIRECTORY_FILE)) {
  const directory = JSON.parse(fs.readFileSync(USER_DIRECTORY_FILE, 'utf8'));
  if (!directory || directory.kind !== 'user-directory' || !Array.isArray(directory.entries)) {
    throw new Error('invalid user directory');
  }
  const aliases = new Map();
  directory.entries.forEach((entry) => {
    for (const [kind, value] of [
      ['username', entry.username],
      ['phone', entry.phone],
      ['email', entry.email]
    ]) {
      if (value) aliases.set(kind + ':' + value, entry);
    }
  });
  userDirectory = {
    byId: (id) => directory.entries.find((entry) => entry.id === String(id || '')) || null,
    byAlias: (kind, value) => aliases.get(kind + ':' + String(value || '').trim().toLowerCase()) || null
  };
}

function shardFor(kind, id) {
  const key = (kind === 'chat' ? 'c:' : 'u:') + String(id || '');
  const fixed = routePlan && Number(routePlan.assignments[key]);
  if (Number.isInteger(fixed) && fixed >= 0 && fixed < SHARDS) return fixed;
  return routeHash(key) % SHARDS;
}

function tokenFrom(req, url) {
  let token = String(req.headers.authorization || '').replace(/^Bearer /i, '');
  if (!token) token = url.searchParams.get('token') || '';
  if (!token) {
    const match = String(req.headers.cookie || '').match(/chris_chat_session=([^;]+)/);
    if (match) token = decodeURIComponent(match[1]);
  }
  return token;
}

function backFor(req, url, body) {
  if (isMediaObjectPath(req.method, url.pathname)) return 0;
  const chat = String(url.pathname || '').match(/^\/api\/chats\/([^/]+)/);
  if (chat && !['direct', 'group', 'face', 'export', 'import'].includes(chat[1])) {
    return shardFor('chat', decodeURIComponent(chat[1]));
  }
  if (/^\/api\/messages\/[^/]+\/recall$/.test(String(url.pathname || ''))) {
    const chatId = body && typeof body === 'object' ? String(body.chatId || '') : '';
    if (chatId) return shardFor('chat', chatId);
  }
  try {
    const token = tokenFrom(req, url);
    const body = token ? Buffer.from(token.split('.')[0], 'base64url').toString('utf8') : '';
    const claims = body ? JSON.parse(body) : null;
    if (claims && claims.sub) return shardFor('user', claims.sub);
  } catch (_) { /* fall through to shard 0 */ }
  if (userDirectory) {
    const candidate = body && typeof body === 'object' ? body : {};
    const values = [
      ['username', candidate.username || candidate.account || url.searchParams.get('u')],
      ['phone', candidate.phone],
      ['email', candidate.email]
    ];
    for (const [kind, value] of values) {
      const entry = value ? userDirectory.byAlias(kind, value) : null;
      if (entry && Number.isInteger(entry.shard) && entry.shard < SHARDS) {
        return entry.shard;
      }
    }
  }
  return 0;
}

function upstreamRequest(target, options, callback) {
  const client = target.protocol === 'https:' ? https : http;
  return client.request(Object.assign({}, options, {
    protocol: target.protocol,
    hostname: target.hostname,
    host: target.hostname,
    port: target.port
  }), callback);
}

function headers(req) {
  const next = Object.assign({}, req.headers);
  const ip = req.socket && req.socket.remoteAddress || '';
  next['x-forwarded-proto'] = 'https';
  next['x-forwarded-for'] = (req.headers['x-forwarded-for']
    ? req.headers['x-forwarded-for'] + ','
    : '') + ip;
  next['x-real-ip'] = ip;
  return next;
}

function safeSocket(socket) {
  if (!socket || socket.__dualGuarded) return;
  socket.__dualGuarded = true;
  socket.on('error', () => {
    try { socket.destroy(); } catch (_) { /* ignore */ }
  });
  if (socket.setNoDelay) socket.setNoDelay(true);
  if (socket.setKeepAlive) socket.setKeepAlive(true, 30000);
}

function isPaymentPath(pathname) {
  return /^\/api\/(?:pay|payment|transfers|redpacket|redpackets|wallet|bills|gifts)(?:\/|$)/.test(pathname)
    || /^\/api\/(?:me\/wallet|mall\/order|shop\/order)(?:\/|$)/.test(pathname);
}

function forward(req, res, body, url, parsedBody) {
  const target = OWNER_TARGETS[backFor(req, url, parsedBody)];
  const upstream = upstreamRequest(target, {
    path: req.url,
    method: req.method,
    headers: headers(req)
  }, (response) => {
    res.writeHead(response.statusCode, response.headers);
    response.pipe(res);
  });
  upstream.on('error', () => {
    if (!res.headersSent) res.writeHead(502, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('dual-cell backend unavailable');
  });
  if (body) upstream.end(body);
  else req.pipe(upstream);
}

function forwardPayment(req, res) {
  const upstream = https.request({
    host: '127.0.0.1',
    port: PAYMENT_UPSTREAM_PORT,
    path: req.url,
    method: req.method,
    headers: headers(req),
    rejectUnauthorized: false
  }, (response) => {
    res.writeHead(response.statusCode, response.headers);
    response.pipe(res);
  });
  upstream.on('error', () => {
    if (!res.headersSent) {
      res.writeHead(503, { 'Content-Type': 'application/json; charset=utf-8' });
    }
    res.end(JSON.stringify({
      ok: false,
      error: '支付系统暂时不可用，请稍后重试',
      code: 'PAYMENT_UPSTREAM_UNAVAILABLE'
    }));
  });
  req.pipe(upstream);
}

const server = https.createServer({
  cert: fs.readFileSync(CERT),
  key: fs.readFileSync(KEY)
}, (req, res) => {
  safeSocket(req.socket);
  const url = new URL(req.url || '/', 'http://x');
  if (isPaymentPath(url.pathname) && PAYMENT_UPSTREAM_PORT > 0) {
    forwardPayment(req, res);
    return;
  }
  if (PAYMENT_FAIL_CLOSED && isPaymentPath(url.pathname)) {
    res.writeHead(503, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({
      ok: false,
      error: '支付系统正在切换到独立权威分区，请稍后再试',
      code: 'DUAL_CELL_PAYMENT_MAINTENANCE'
    }));
    return;
  }
  const bodyPath = /^\/api\/(login|account\/state|messages\/[^/]+\/recall)/.test(url.pathname)
    && req.method === 'POST';
  if (bodyPath) {
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size <= 256 * 1024) chunks.push(chunk);
    });
    req.on('end', () => {
      let body = null;
      try { body = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch (_) { body = null; }
      forward(req, res, Buffer.concat(chunks), url, body);
    });
    req.on('error', () => {
      if (!res.headersSent) res.writeHead(400);
      res.end();
    });
    return;
  }
  forward(req, res, null, url);
});

server.on('upgrade', (req, socket, head) => {
  safeSocket(socket);
  const target = OWNER_TARGETS[
    backFor(req, new URL(req.url || '/', 'http://x'), null)
  ];
  const upstream = upstreamRequest(target, {
    path: req.url,
    method: req.method,
    headers: headers(req)
  });
  upstream.on('upgrade', (response, upstreamSocket, upstreamHead) => {
    safeSocket(upstreamSocket);
    let raw = 'HTTP/1.1 101 Switching Protocols\r\n';
    Object.keys(response.headers).forEach((key) => {
      raw += key + ': ' + response.headers[key] + '\r\n';
    });
    socket.write(raw + '\r\n');
    if (upstreamHead && upstreamHead.length) upstreamSocket.unshift(upstreamHead);
    if (head && head.length) upstreamSocket.write(head);
    upstreamSocket.pipe(socket);
    socket.pipe(upstreamSocket);
  });
  upstream.on('response', (response) => {
    let raw = 'HTTP/1.1 ' + response.statusCode + ' '
      + (response.statusMessage || '') + '\r\n';
    Object.keys(response.headers).forEach((key) => {
      raw += key + ': ' + response.headers[key] + '\r\n';
    });
    socket.write(raw + '\r\n');
    response.pipe(socket);
  });
  upstream.on('error', () => {
    try { socket.destroy(); } catch (_) { /* ignore */ }
  });
  upstream.end();
});

server.on('connection', safeSocket);
server.on('secureConnection', safeSocket);
server.on('tlsClientError', (_, socket) => safeSocket(socket));
server.on('clientError', (_, socket) => safeSocket(socket));
server.keepAliveTimeout = 65000;
server.headersTimeout = 70000;
server.requestTimeout = 0;
server.timeout = 0;
server.maxConnections = Number(process.env.TLS_MAX_CONNECTIONS || 20000);

process.on('SIGHUP', () => {
  try {
    reloadGatewayRouting();
  } catch (error) {
    console.error(JSON.stringify({
      service: 'dual-cell-tls-proxy',
      event: 'routing-reload-failed',
      error: String(error && error.message || error)
    }));
  }
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(JSON.stringify({
    service: 'dual-cell-tls-proxy',
    port: PORT,
    shards: SHARDS,
    ownerPorts: OWNER_PORTS,
    ownerTargets: OWNER_TARGETS.map((target) => target.origin),
    routePlanHash: routePlan ? routePlan.hash : ''
  }));
});
