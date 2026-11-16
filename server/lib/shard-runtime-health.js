'use strict';

const { verifyRoutePlan } = require('./shard-route-plan');

function sameArray(left, right) {
  return JSON.stringify(left || []) === JSON.stringify(right || []);
}

function validateRoutePlan(routePlan, manifest) {
  const verification = verifyRoutePlan(routePlan);
  const failures = verification.failures.map((row) => ({
    code: 'route-plan-' + String(row.kind || 'invalid'),
    details: row
  }));
  if (!verification.ok) return { ok: false, failures, verification };
  if (routePlan.topologyId !== manifest.topologyId) {
    failures.push({
      code: 'route-plan-topology-mismatch',
      expected: manifest.topologyId,
      actual: routePlan.topologyId
    });
  }
  if (Number(routePlan.shardCount) !== Number(manifest.shardCount)) {
    failures.push({
      code: 'route-plan-shard-count-mismatch',
      expected: manifest.shardCount,
      actual: routePlan.shardCount
    });
  }
  const manifestPorts = (manifest.shards || []).map((row) => Number(row.backendPort));
  if (!sameArray(routePlan.ports, manifestPorts)) {
    failures.push({
      code: 'route-plan-ports-mismatch',
      expected: manifestPorts,
      actual: routePlan.ports || []
    });
  }
  return {
    ok: failures.length === 0,
    failures,
    verification
  };
}

function evaluateShardHealth(responseBody, expected) {
  const opts = expected || {};
  const shard = opts.shard || {};
  const data = responseBody && responseBody.ok === true
    ? responseBody.data || {}
    : null;
  const failures = [];
  const fail = (code, details) => failures.push(details === undefined
    ? { code }
    : { code, details });

  if (!data || typeof data !== 'object') {
    fail('health-invalid');
    return { ok: false, failures, data: null };
  }
  if (Number(data.port) !== Number(shard.backendPort)) {
    fail('health-port-mismatch', {
      expected: Number(shard.backendPort),
      actual: data.port
    });
  }
  if (String(data.shardId) !== String(shard.id)) {
    fail('health-shard-id-mismatch', {
      expected: String(shard.id),
      actual: String(data.shardId || '')
    });
  }
  if (String(data.runtimeService || '') !== String(shard.service || '')) {
    fail('runtime-service-mismatch', {
      expected: String(shard.service || ''),
      actual: String(data.runtimeService || '')
    });
  }
  if (String(data.runtimeManifestHash || '') !== String(opts.runtimeManifestHash || '')) {
    fail('runtime-manifest-mismatch', {
      expected: String(opts.runtimeManifestHash || ''),
      actual: String(data.runtimeManifestHash || '')
    });
  }
  if (String(data.runtimeTopologyId || '') !== String(opts.runtimeTopologyId || '')) {
    fail('runtime-topology-mismatch', {
      expected: String(opts.runtimeTopologyId || ''),
      actual: String(data.runtimeTopologyId || '')
    });
  }
  if (opts.routePlan) {
    if (String(data.chatRoutePlanHash || '') !== String(opts.routePlan.hash || '')) {
      fail('chat-route-plan-hash-mismatch', {
        expected: String(opts.routePlan.hash || ''),
        actual: String(data.chatRoutePlanHash || '')
      });
    }
    if (opts.routePlanFileHash
        && String(data.chatRoutePlanFileHash || '') !== String(opts.routePlanFileHash)) {
      fail('chat-route-plan-file-hash-mismatch', {
        expected: String(opts.routePlanFileHash),
        actual: String(data.chatRoutePlanFileHash || '')
      });
    }
    if (String(data.chatRouteTopologyId || '') !== String(opts.routePlan.topologyId || '')) {
      fail('chat-route-topology-mismatch', {
        expected: String(opts.routePlan.topologyId || ''),
        actual: String(data.chatRouteTopologyId || '')
      });
    }
    if (opts.requireRouteEnforced === true && data.chatRoutePlanEnforced !== true) {
      fail('chat-route-plan-not-enforced');
    }
    if (opts.requireRouteDormant === true && data.chatRoutePlanEnforced !== false) {
      fail('chat-route-plan-not-dormant');
    }
  }
  return { ok: failures.length === 0, failures, data };
}

module.exports = {
  validateRoutePlan,
  evaluateShardHealth
};
