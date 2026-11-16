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
let shardWriteFrozen = false;
let shardFenceEpoch = 0;
let shardWriteFreezeReason = '';

function chatOwnerPort(chatId) {
  const count = Math.max(1, Number(process.env.SHARD_COUNT) || 1);
  if (count <= 1 || !chatRoutePlanEnforced) return PORT;
  const base = Number(process.env.SHARD_BASE_PORT) || 5299;
  return base + chatOwnerShard(chatRoutePlan, chatId, count) * 100;
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

const OWNER_ROUTING_ENDPOINT = `
    if (parsed.pathname === '/__shard/owner-routing') {
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
      const enabled = body.enabled === true;
      if (enabled) {
        if (!chatRoutePlan) return fail(res, 409, '聊天路由计划尚未加载');
        if (String(body.planHash || '') !== chatRoutePlan.hash
            || String(body.fileSha256 || '') !== chatRoutePlan.fileHash) {
          return fail(res, 409, '聊天路由计划哈希不一致');
        }
      }
      chatRoutePlanEnforced = enabled;
      return ok(res, {
        enabled: chatRoutePlanEnforced,
        planHash: chatRoutePlan ? chatRoutePlan.hash : '',
        fileSha256: chatRoutePlan ? chatRoutePlan.fileHash : '',
        chatOwnerForwards: chatOwnerForwardCount
      });
    }
`.trimEnd();

const WRITE_FREEZE_ENDPOINT = `
    if (parsed.pathname === '/__shard/write-freeze') {
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
      if (!chatRoutePlan) return fail(res, 409, '聊天路由计划尚未加载');
      if (String(body.planHash || '') !== chatRoutePlan.hash
          || String(body.fileSha256 || '') !== chatRoutePlan.fileHash) {
        return fail(res, 409, '聊天路由计划哈希不一致');
      }
      const frozen = body.frozen === true;
      const epoch = Number(body.epoch);
      if (!Number.isInteger(epoch) || epoch <= 0) {
        return fail(res, 422, 'fencing epoch 无效');
      }
      if (epoch !== shardFenceEpoch + 1) {
        return fail(res, 409, 'fencing epoch 已过期');
      }
      shardWriteFrozen = frozen;
      shardFenceEpoch = epoch;
      shardWriteFreezeReason = frozen
        ? String(body.reason || 'physical-shard-cutover').slice(0, 120)
        : '';
      return ok(res, {
        frozen: shardWriteFrozen,
        fenceEpoch: shardFenceEpoch,
        reason: shardWriteFreezeReason,
        planHash: chatRoutePlan.hash,
        fileSha256: chatRoutePlan.fileHash
      });
    }
`.trimEnd();

const WRITE_FREEZE_GATE = `
  const readOnlyHttpMethod = req.method === 'GET' || req.method === 'HEAD'
    || req.method === 'OPTIONS';
  if (shardWriteFrozen && parsed.pathname !== '/__shard/write-freeze'
      && !readOnlyHttpMethod) {
    return fail(res, 503, '正在切换数据分片，请稍后重试');
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

function patchProductionServerSource(source, actualSha256, expectedSha256) {
  const changes = [];
  source = replaceOnce(
    source,
    "const ws = require('./lib/ws');",
    "const ws = require('./lib/ws');\n"
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
    "  const parsed = new URL(req.url, 'http://' + (req.headers.host || 'localhost'));",
    "  const parsed = new URL(req.url, 'http://' + (req.headers.host || 'localhost'));\n"
      + WRITE_FREEZE_GATE,
    'write-freeze-gate',
    changes
  );
  source = replaceOnce(
    source,
    'function sendBatchToUser(userId, payloads) {',
    CHAT_OWNER_RUNTIME + '\n\nfunction sendBatchToUser(userId, payloads) {',
    'chat-owner-runtime',
    changes
  );
  source = replaceOnce(
    source,
    "  if (msg.type === 'ping') {",
    "  if (shardWriteFrozen && !['ping', 'call', 'live'].includes(msg.type)) {\n"
      + "    ws.sendText(socket, JSON.stringify({ type: 'error', error: "
      + "'正在切换数据分片，请稍后重试', code: 'SHARD_WRITE_FROZEN',"
      + " fenceEpoch: shardFenceEpoch }));\n"
      + "    return;\n"
      + "  }\n"
      + "  const chatScopedType = ['ack', 'typing', 'pat', 'read', 'send', 'shake'].includes(msg.type);\n"
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
      chatOwnerForwards: chatOwnerForwardCount,
      writeFrozen: shardWriteFrozen,
      fenceEpoch: shardFenceEpoch,
      writeFreezeReason: shardWriteFreezeReason
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
    "function isAdminPath(pathname) {\n"
      + "  return pathname === '/manage.html' || pathname === '/admin.html' || pathname === '/ai.html' ||\n"
      + "    pathname.indexOf('/api/ops') === 0 || pathname.indexOf('/api/admin') === 0;\n"
      + '}',
    "function isAdminPath(pathname) {\n"
      + "  return pathname === '/manage.html' || pathname === '/admin.html' || pathname === '/ai.html' ||\n"
      + "    pathname === '/shard-maintenance.html' ||\n"
      + "    pathname.indexOf('/api/ops') === 0 || pathname.indexOf('/api/admin') === 0;\n"
      + '}',
    'admin-path',
    changes
  );
  source = replaceOnce(
    source,
    "    if (parsed.pathname === '/api/internal/user-row' && req.method === 'POST') {",
    OWNER_ROUTING_ENDPOINT + "\n" + WRITE_FREEZE_ENDPOINT + "\n" + CHAT_ACTION_ENDPOINT
      + "\n    if (parsed.pathname === '/api/internal/user-row' && req.method === 'POST') {",
    'chat-action-endpoint',
    changes
  );
  return {
    ok: true,
    profile: 'production-cb937047',
    sourceSha256: actualSha256,
    expectedSha256,
    outputSha256: hash(Buffer.from(source)),
    changes,
    source,
    helperFiles: helperFileRows()
  };
}

function helperFileRows() {
  return [
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
  if (source.includes('const H5_GEN_DIR =') && source.includes('const SHARD_DIR =')) {
    return patchProductionServerSource(source, actualSha256, expectedSha256);
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
    "  const parsed = new URL(req.url, 'http://' + (req.headers.host || 'localhost'));",
    "  const parsed = new URL(req.url, 'http://' + (req.headers.host || 'localhost'));\n"
      + WRITE_FREEZE_GATE,
    'write-freeze-gate',
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
    "  if (shardWriteFrozen && !['ping', 'call', 'live'].includes(msg.type)) {\n"
      + "    ws.sendText(socket, JSON.stringify({ type: 'error', error: "
      + "'正在切换数据分片，请稍后重试', code: 'SHARD_WRITE_FROZEN',"
      + " fenceEpoch: shardFenceEpoch }));\n"
      + "    return;\n"
      + "  }\n"
      + "  const chatScopedType = ['ack', 'typing', 'pat', 'read', 'send', 'shake'].includes(msg.type);\n"
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
      chatOwnerForwards: chatOwnerForwardCount,
      writeFrozen: shardWriteFrozen,
      fenceEpoch: shardFenceEpoch,
      writeFreezeReason: shardWriteFreezeReason
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
    OWNER_ROUTING_ENDPOINT + "\n" + WRITE_FREEZE_ENDPOINT + "\n" + CHAT_ACTION_ENDPOINT
      + "\n    if (parsed.pathname === '/__shard/relay') {",
    'chat-action-endpoint',
    changes
  );
  return {
    ok: true,
    profile: 'git-stable-bc09897',
    sourceSha256: actualSha256,
    expectedSha256,
    outputSha256: hash(Buffer.from(source)),
    changes,
    source,
    helperFiles: helperFileRows()
  };
}

module.exports = {
  STABLE_SERVER_SHA256,
  patchServerSource
};
