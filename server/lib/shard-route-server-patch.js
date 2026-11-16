'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const STABLE_SERVER_SHA256 = 'cb937047456b6c6bf4aa1b174b4d1edb397e54c1e47ff60f6ca0341b4215007c';
const SERVER_ROOT = path.resolve(__dirname, '..');

const ROUTE_INIT = `
let chatRoutePlan = null;
let chatRoutePlanEnforced = false;
if (process.env.SHARD_ROUTE_PLAN_FILE) {
  chatRoutePlan = loadChatRoutePlan(process.env.SHARD_ROUTE_PLAN_FILE, {
    shardCount: Number(process.env.SHARD_COUNT) || 1,
    basePort: Number(process.env.SHARD_BASE_PORT) || 5299,
    shardId: Number(process.env.SHARD_ID),
    port: PORT,
    fileSha256: process.env.SHARD_ROUTE_PLAN_FILE_SHA256
  });
  console.log('[聊天路由] topology=' + chatRoutePlan.topologyId
    + ' hash=' + chatRoutePlan.hash.slice(0, 12)
    + ' shards=' + chatRoutePlan.shardCount);
}
const routePlanFlag = String(process.env.SHARD_ROUTE_PLAN_ENFORCED || '').trim();
if (routePlanFlag && routePlanFlag !== '0' && routePlanFlag !== '1') {
  throw new Error('SHARD_ROUTE_PLAN_ENFORCED must be 0 or 1');
}
chatRoutePlanEnforced = routePlanFlag === '1';
if (chatRoutePlanEnforced && !chatRoutePlan) {
  throw new Error('SHARD_ROUTE_PLAN_ENFORCED requires SHARD_ROUTE_PLAN_FILE');
}
if (chatRoutePlan) {
  console.log('[聊天路由] mode=' + (chatRoutePlanEnforced ? 'enforced' : 'dormant'));
}
let shardRuntimeIdentity = null;
if (process.env.SHARD_RUNTIME_MANIFEST) {
  const shardTopologyFile = process.env.SHARD_TOPOLOGY_FILE
    ? path.resolve(process.env.SHARD_TOPOLOGY_FILE)
    : path.join(ROOT, 'shard-topologies.json');
  const runtimeManifest = loadManifest(
    path.resolve(process.env.SHARD_RUNTIME_MANIFEST),
    { topologyFile: shardTopologyFile }
  );
  shardRuntimeIdentity = assertRunningShard(runtimeManifest, {
    shardId: process.env.SHARD_ID,
    port: PORT
  });
  if (chatRoutePlan
      && chatRoutePlan.topologyId !== shardRuntimeIdentity.topologyId) {
    throw new Error('route plan topology mismatch: plan='
      + chatRoutePlan.topologyId + ' runtime='
      + shardRuntimeIdentity.topologyId);
  }
  console.log('[分片身份] ' + shardRuntimeIdentity.service
    + ' port=' + shardRuntimeIdentity.backendPort
    + ' topology=' + shardRuntimeIdentity.topologyId
    + ' manifest=' + shardRuntimeIdentity.manifestHash.slice(0, 12));
}
`.trim();

const CHAT_OWNER_RUNTIME = `
const chatOwnerAgent = new http.Agent({ keepAlive: true, maxSockets: 256 });
const chatOwnerSockets = new Map();
let chatOwnerForwardCount = 0;

function chatOwnerPort(chatId) {
  const count = Math.max(1, Number(process.env.SHARD_COUNT) || 1);
  if (count <= 1) return PORT;
  const base = Number(process.env.SHARD_BASE_PORT) || 5299;
  const plan = chatRoutePlanEnforced ? chatRoutePlan : null;
  return base + chatOwnerShard(plan, chatId, count) * 100;
}

function chatOwnerRelaySocket(actor, body) {
  const key = actor.id + '|' + String(body.deviceId || '');
  let relaySocket = chatOwnerSockets.get(key);
  if (relaySocket) return relaySocket;
  relaySocket = {
    __appBuild: String(body.appBuild || '') || 'shard-chat',
    __deviceId: String(body.deviceId || '') || 'shard-chat:' + actor.id,
    __kind: String(body.deviceKind || '') || 'phone',
    encrypted: false,
    sendText(text) {
      try {
        sendTo(actor.id, JSON.parse(String(text || '{}')));
      } catch (_) { /* ignore malformed local response */ }
    },
    destroy() {}
  };
  if (chatOwnerSockets.size > 2000) chatOwnerSockets.clear();
  chatOwnerSockets.set(key, relaySocket);
  return relaySocket;
}

function forwardChatActionToOwner(actorId, msg, socket) {
  const ownerPort = chatOwnerPort(msg.chatId);
  if (!ownerPort || ownerPort === PORT) return false;
  chatOwnerForwardCount += 1;
  const body = JSON.stringify({
    actorId: String(actorId || ''),
    deviceId: String(socket && socket.__deviceId || ''),
    appBuild: String(socket && socket.__appBuild || ''),
    deviceKind: String(socket && socket.__kind || ''),
    payload: msg
  });
  const request = http.request({
    host: '127.0.0.1',
    port: ownerPort,
    path: '/__shard/chat-action',
    method: 'POST',
    agent: chatOwnerAgent,
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(body),
      'X-Shard-Relay': db.secret || ''
    }
  }, (response) => response.resume());
  request.setTimeout(1800, () => request.destroy());
  request.on('error', () => {});
  request.end(body);
  return true;
}
`.trim();

const CHAT_ACTION_ENDPOINT = `
    if (parsed.pathname === '/__shard/chat-action') {
      if (req.method !== 'POST') return fail(res, 405, 'Method Not Allowed');
      const supplied = String(req.headers['x-shard-relay'] || '');
      const expected = String(db.secret || '');
      const suppliedBuffer = Buffer.from(supplied);
      const expectedBuffer = Buffer.from(expected);
      if (!expected || suppliedBuffer.length !== expectedBuffer.length
          || !crypto.timingSafeEqual(suppliedBuffer, expectedBuffer)) {
        return fail(res, 403, '禁止访问');
      }
      const body = await readBody(req);
      const actor = findUser(str(body.actorId, 80));
      if (!actor || !body.payload || typeof body.payload !== 'object') {
        return fail(res, 422, '会话操作不完整');
      }
      const relaySocket = chatOwnerRelaySocket(actor, body);
      handleClientMessage(actor, relaySocket, JSON.stringify(body.payload));
      return ok(res, { accepted: true });
    }
`.trimEnd();

function hash(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function replaceOnce(source, marker, replacement, name, changes) {
  const count = source.split(marker).length - 1;
  if (count !== 1) {
    throw new Error(name + ' anchor count=' + count + ' (expected 1)');
  }
  changes.push(name);
  return source.replace(marker, replacement);
}

function replaceCount(source, marker, replacement, expected, name, changes) {
  const count = source.split(marker).length - 1;
  if (count !== expected) {
    throw new Error(name + ' anchor count=' + count + ' (expected ' + expected + ')');
  }
  changes.push(name);
  return source.split(marker).join(replacement);
}

function patchServerSource(input, options) {
  const opts = options || {};
  const raw = Buffer.isBuffer(input) ? input : Buffer.from(String(input || ''));
  const actualSha256 = hash(raw);
  const expectedSha256 = String(opts.expectedSha256 || STABLE_SERVER_SHA256).toLowerCase();
  if (actualSha256 !== expectedSha256) {
    throw new Error('stable server hash mismatch: expected=' + expectedSha256
      + ' actual=' + actualSha256);
  }
  let source = raw.toString('utf8').replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  if (source.includes('SHARD_ROUTE_PLAN_FILE')) {
    throw new Error('server source already contains route plan integration');
  }
  const changes = [];
  source = replaceOnce(
    source,
    "const { resolveTopology } = require('./lib/shard-topology');",
    "const { resolveTopology } = require('./lib/shard-topology');\n"
      + "const { loadManifest, assertRunningShard } = require('./lib/shard-runtime-manifest');\n"
      + "const { loadChatRoutePlan, chatOwnerShard } = require('./lib/chat-route-plan');",
    'requires',
    changes
  );
  source = replaceOnce(
    source,
    'const PORT = Number(process.env.PORT || 5180);',
    'const PORT = Number(process.env.PORT || 5180);\n' + ROUTE_INIT,
    'route-runtime',
    changes
  );
  source = replaceOnce(
    source,
    'function peerOnlineSet(port) {',
    CHAT_OWNER_RUNTIME + '\n\nfunction peerOnlineSet(port) {',
    'chat-owner-runtime',
    changes
  );
  source = replaceOnce(
    source,
    "  if (msg.type === 'ping') {",
    "  const chatScopedType = ['ack', 'typing', 'pat', 'read', 'send', 'shake'].includes(msg.type);\n"
      + "  if (chatScopedType && msg.chatId && PORT !== chatOwnerPort(msg.chatId)) {\n"
      + "    forwardChatActionToOwner(user.id, msg, socket);\n"
      + "    return;\n"
      + "  }\n\n"
      + "  if (msg.type === 'ping') {",
    'client-routing',
    changes
  );
  source = replaceOnce(
    source,
    "  if (parts[0] === 'health') { ok(res, { service: 'chris-chat', time: now() }); return; }",
    `  if (parts[0] === 'health') {
    ok(res, {
      service: 'chris-chat',
      time: now(),
      port: PORT,
      shardId: process.env.SHARD_ID || '',
      runtimeManifestHash: shardRuntimeIdentity ? shardRuntimeIdentity.manifestHash : '',
      runtimeTopologyId: shardRuntimeIdentity ? shardRuntimeIdentity.topologyId : '',
      runtimeService: shardRuntimeIdentity ? shardRuntimeIdentity.service : '',
      chatRoutePlanHash: chatRoutePlan ? chatRoutePlan.hash : '',
      chatRoutePlanFileHash: chatRoutePlan ? chatRoutePlan.fileHash : '',
      chatRouteTopologyId: chatRoutePlan ? chatRoutePlan.topologyId : '',
      chatRoutePlanEnforced,
      chatOwnerForwards: chatOwnerForwardCount
    });
    return;
  }`,
    'health-fields',
    changes
  );
  source = replaceCount(
    source,
    '/^\\/(index|m|install|admin|admin2|manage|ai|login)\\.html$/i',
    '/^\\/(index|m|install|admin|admin2|manage|ai|login|shard-maintenance)\\.html$/i',
    1,
    'tls-page',
    changes
  );
  source = replaceCount(
    source,
    '/^\\/(manage|admin|admin2|ai)\\.html$/i',
    '/^\\/(manage|admin|admin2|ai|shard-maintenance)\\.html$/i',
    2,
    'admin-page-regex',
    changes
  );
  source = replaceCount(
    source,
    '/^\\/(manage|admin|admin2|ai|index)\\.html$/i',
    '/^\\/(manage|admin|admin2|ai|index|shard-maintenance)\\.html$/i',
    1,
    'admin-entry-regex',
    changes
  );
  source = replaceCount(
    source,
    '/^(index|admin|admin2|manage|ai)\\.html$/i',
    '/^(index|admin|admin2|manage|ai|shard-maintenance)\\.html$/i',
    1,
    'static-page-regex',
    changes
  );
  source = replaceOnce(
    source,
    "    pathname === '/ai.html' || pathname === '/mall-admin.html' ||",
    "    pathname === '/ai.html' || pathname === '/mall-admin.html' ||\n"
      + "    pathname === '/shard-maintenance.html' ||",
    'admin-path',
    changes
  );
  source = replaceOnce(
    source,
    "    if (parsed.pathname === '/__shard/relay') {",
    CHAT_ACTION_ENDPOINT + "\n    if (parsed.pathname === '/__shard/relay') {",
    'chat-action-endpoint',
    changes
  );
  const helperFiles = [
    'lib/shard-route-plan.js',
    'lib/chat-route-plan.js',
    'lib/shard-runtime-manifest.js',
    'lib/shard-topology.js'
  ].map((relative) => {
    const file = path.join(SERVER_ROOT, relative);
    return {
      path: relative,
      sha256: hash(fs.readFileSync(file))
    };
  });
  return {
    ok: true,
    sourceSha256: actualSha256,
    expectedSha256,
    outputSha256: hash(Buffer.from(source)),
    changes,
    source,
    helperFiles
  };
}

module.exports = {
  STABLE_SERVER_SHA256,
  patchServerSource
};
