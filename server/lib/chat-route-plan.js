'use strict';

const fs = require('fs');
const path = require('path');
const { resolveRoute, verifyRoutePlan } = require('./shard-route-plan');

function expectedPorts(shardCount, basePort) {
  const count = Number(shardCount);
  const base = Number(basePort);
  return Array.from({ length: count }, (_, index) => base + index * 100);
}

function loadChatRoutePlan(file, options) {
  const opts = options || {};
  const shardCount = Number(opts.shardCount);
  const basePort = Number(opts.basePort);
  const shardId = Number(opts.shardId);
  const port = Number(opts.port);
  if (!file) return null;
  if (!Number.isInteger(shardCount) || shardCount < 2) {
    throw new Error('SHARD_COUNT is invalid');
  }
  if (!Number.isInteger(basePort) || basePort <= 0) {
    throw new Error('SHARD_BASE_PORT is invalid');
  }
  if (!Number.isInteger(shardId) || shardId < 0 || shardId >= shardCount) {
    throw new Error('SHARD_ID is invalid');
  }
  if (!Number.isInteger(port) || port <= 0) {
    throw new Error('PORT is invalid');
  }
  const resolved = path.resolve(String(file));
  const plan = JSON.parse(fs.readFileSync(resolved, 'utf8'));
  const verification = verifyRoutePlan(plan);
  if (!verification.ok) {
    throw new Error('route plan verification failed: '
      + JSON.stringify(verification.failures.slice(0, 10)));
  }
  const topologyId = String(plan.topologyId || '').trim();
  if (!topologyId) {
    throw new Error('route plan topologyId is required');
  }
  if (Number(plan.shardCount) !== shardCount) {
    throw new Error('route plan shardCount mismatch: plan=' + plan.shardCount
      + ' runtime=' + shardCount);
  }
  const ports = expectedPorts(shardCount, basePort);
  if (JSON.stringify(plan.ports || []) !== JSON.stringify(ports)) {
    throw new Error('route plan ports mismatch: plan=' + JSON.stringify(plan.ports)
      + ' runtime=' + JSON.stringify(ports));
  }
  const expectedPort = basePort + shardId * 100;
  if (port !== expectedPort) {
    throw new Error('runtime port mismatch: shard=' + shardId
      + ' expected=' + expectedPort + ' actual=' + port);
  }
  return {
    file: resolved,
    plan,
    hash: String(plan.hash || ''),
    topologyId,
    shardCount,
    ports
  };
}

function chatOwnerShard(routePlan, chatId, shardCount) {
  if (routePlan) {
    return resolveRoute(routePlan.plan || routePlan, 'chat', chatId);
  }
  const { routeShard } = require('./shard-route-plan');
  return routeShard('c:' + String(chatId || ''), shardCount);
}

module.exports = {
  expectedPorts,
  loadChatRoutePlan,
  chatOwnerShard
};
