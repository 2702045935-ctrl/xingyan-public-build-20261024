'use strict';

const assert = require('assert');
const { buildRoutePlan } = require('../lib/shard-route-plan');
const {
  validateRoutePlan,
  evaluateShardHealth
} = require('../lib/shard-runtime-health');

const ports = [7080, 7180, 7280, 7380, 7480, 7580, 7680];
const manifest = {
  topologyId: 'server-b-mainline-shards-7',
  shardCount: 7,
  shards: ports.map((backendPort, id) => ({
    id,
    service: 'xingyan-mainline-shard@' + id + '.service',
    backendPort
  }))
};
const routePlan = buildRoutePlan({
  users: [{ id: 'u1' }, { id: 'u2' }],
  chats: [{ id: 'c1' }, { id: 'c2' }],
  shardCount: 7,
  ports,
  topologyId: manifest.topologyId,
  baselineDate: '2026-11-16',
  createdAt: '2026-11-16T00:00:00Z'
});
const expected = {
  shard: manifest.shards[3],
  runtimeManifestHash: 'manifest-hash',
  runtimeTopologyId: manifest.topologyId,
  routePlan,
  routePlanFileHash: 'route-plan-file-hash',
  requireRouteDormant: true
};
const body = {
  ok: true,
  data: {
    port: 7380,
    shardId: '3',
    runtimeService: manifest.shards[3].service,
    runtimeManifestHash: 'manifest-hash',
    runtimeTopologyId: manifest.topologyId,
    chatRoutePlanHash: routePlan.hash,
    chatRoutePlanFileHash: 'route-plan-file-hash',
    chatRouteTopologyId: routePlan.topologyId,
    chatRoutePlanEnforced: false
  }
};

assert.strictEqual(validateRoutePlan(routePlan, manifest).ok, true);
assert.strictEqual(evaluateShardHealth(body, expected).ok, true);

const wrongManifest = JSON.parse(JSON.stringify(body));
wrongManifest.data.runtimeManifestHash = 'wrong';
assert.ok(evaluateShardHealth(wrongManifest, expected).failures.some(
  (row) => row.code === 'runtime-manifest-mismatch'
));

const wrongPlan = JSON.parse(JSON.stringify(body));
wrongPlan.data.chatRoutePlanHash = 'wrong';
assert.ok(evaluateShardHealth(wrongPlan, expected).failures.some(
  (row) => row.code === 'chat-route-plan-hash-mismatch'
));

const wrongPlanFile = JSON.parse(JSON.stringify(body));
wrongPlanFile.data.chatRoutePlanFileHash = 'wrong';
assert.ok(evaluateShardHealth(wrongPlanFile, expected).failures.some(
  (row) => row.code === 'chat-route-plan-file-hash-mismatch'
));

const enforced = JSON.parse(JSON.stringify(body));
enforced.data.chatRoutePlanEnforced = true;
assert.ok(evaluateShardHealth(enforced, expected).failures.some(
  (row) => row.code === 'chat-route-plan-not-dormant'
));
assert.strictEqual(evaluateShardHealth(enforced, Object.assign({}, expected, {
  requireRouteDormant: false,
  requireRouteEnforced: true
})).ok, true);

const wrongTopologyPlan = buildRoutePlan({
  users: [{ id: 'u1' }, { id: 'u2' }],
  chats: [{ id: 'c1' }, { id: 'c2' }],
  shardCount: 7,
  ports,
  topologyId: 'wrong-topology',
  baselineDate: '2026-11-16',
  createdAt: '2026-11-16T00:00:00Z'
});
assert.ok(validateRoutePlan(wrongTopologyPlan, manifest).failures.some(
  (row) => row.code === 'route-plan-topology-mismatch'
));

console.log('shard-runtime-health: passed');
