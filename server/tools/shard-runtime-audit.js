'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { loadManifest } = require('../lib/shard-runtime-manifest');
const {
  validateRoutePlan,
  evaluateShardHealth
} = require('../lib/shard-runtime-health');

const ROOT = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
const manifestArg = args.find((value) => value.startsWith('--manifest='));
const topologyArg = args.find((value) => value.startsWith('--topology='));
const routePlanArg = args.find((value) => value.startsWith('--route-plan='));
const routePlanFileShaArg = args.find((value) =>
  value.startsWith('--route-plan-file-sha256=')
);
const manifestFile = manifestArg
  ? path.resolve(manifestArg.slice('--manifest='.length))
  : path.join(ROOT, 'shard-runtime-production.json');
const topologyFile = topologyArg
  ? path.resolve(topologyArg.slice('--topology='.length))
  : path.join(ROOT, 'shard-topologies.json');
const routePlanFile = routePlanArg
  ? path.resolve(routePlanArg.slice('--route-plan='.length))
  : '';
const routePlanRaw = routePlanFile ? fs.readFileSync(routePlanFile) : null;
const routePlanFileHash = routePlanRaw
  ? crypto.createHash('sha256').update(routePlanRaw).digest('hex')
  : '';
const expectedRoutePlanFileHash = routePlanFileShaArg
  ? routePlanFileShaArg.slice('--route-plan-file-sha256='.length).toLowerCase()
  : '';
const routePlan = routePlanRaw
  ? JSON.parse(routePlanRaw.toString('utf8'))
  : null;
const checkSystemd = !args.includes('--no-systemd');
const checkCode = !args.includes('--no-code');
const requireRouteEnforced = args.includes('--require-route-enforced');
const requireRouteDormant = args.includes('--require-route-dormant');
if (requireRouteEnforced && requireRouteDormant) {
  throw new Error('--require-route-enforced and --require-route-dormant are exclusive');
}
if ((requireRouteEnforced || requireRouteDormant) && !routePlan) {
  throw new Error('route enforcement checks require --route-plan=FILE');
}
if (routePlanFileShaArg && !routePlan) {
  throw new Error('--route-plan-file-sha256 requires --route-plan=FILE');
}
if (!expectedRoutePlanFileHash
    && (requireRouteEnforced || requireRouteDormant)) {
  throw new Error('route mode checks require --route-plan-file-sha256=SHA256');
}
if (expectedRoutePlanFileHash
    && !/^[a-f0-9]{64}$/.test(expectedRoutePlanFileHash)) {
  throw new Error('--route-plan-file-sha256 must be a SHA256 hex digest');
}
const loaded = loadManifest(manifestFile, { topologyFile });
const routePlanContentAudit = routePlan
  ? validateRoutePlan(routePlan, loaded.manifest)
  : { ok: true, failures: [] };
const routePlanFileOk = !expectedRoutePlanFileHash
  || routePlanFileHash === expectedRoutePlanFileHash;
const routePlanFailures = [
  ...routePlanContentAudit.failures,
  ...(routePlanFileOk ? [] : [{
    code: 'route-plan-file-hash-mismatch',
    expected: expectedRoutePlanFileHash,
    actual: routePlanFileHash
  }])
];
const routePlanAudit = {
  ok: routePlanContentAudit.ok && routePlanFileOk,
  failures: routePlanFailures
};

function run(command, commandArgs) {
  const result = spawnSync(command, commandArgs, {
    encoding: 'utf8',
    timeout: 5000,
    windowsHide: true
  });
  return {
    ok: result.status === 0,
    value: String(result.stdout || '').trim(),
    error: String(result.stderr || '').trim()
  };
}

function codeHash() {
  if (!checkCode) return '';
  const file = path.join(loaded.manifest.programDir, 'server.js');
  try {
    return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
  } catch (error) {
    return 'ERROR:' + error.message;
  }
}

async function health(port) {
  const response = await fetch('http://127.0.0.1:' + port + '/api/health', {
    signal: AbortSignal.timeout(3000)
  });
  const body = await response.json();
  return {
    status: response.status,
    ok: response.ok && body && body.ok === true,
    body
  };
}

async function main() {
  const actualCodeHash = codeHash();
  const rows = [];
  for (const shard of loaded.manifest.shards) {
    const active = checkSystemd
      ? run('systemctl', ['is-active', shard.service])
      : { ok: true, value: 'unchecked', error: '' };
    const pid = checkSystemd
      ? run('systemctl', ['show', shard.service, '-p', 'MainPID', '--value'])
      : { ok: true, value: '', error: '' };
    let healthResult;
    try {
      healthResult = await health(shard.backendPort);
    } catch (error) {
      healthResult = { status: 0, ok: false, error: error.message, body: null };
    }
    const healthAudit = evaluateShardHealth(healthResult.body, {
      shard,
      runtimeManifestHash: loaded.hash,
      runtimeTopologyId: loaded.manifest.topologyId,
      routePlan,
      routePlanFileHash: expectedRoutePlanFileHash || routePlanFileHash,
      requireRouteEnforced,
      requireRouteDormant
    });
    rows.push({
      id: shard.id,
      service: shard.service,
      backendPort: shard.backendPort,
      state: active.value,
      pid: pid.value,
      health: healthResult,
      healthAudit,
      failures: [
        ...(!checkSystemd || (active.ok && active.value === 'active')
          ? []
          : ['service-not-active']),
        ...(!checkSystemd || (pid.ok && Number(pid.value) > 0) ? [] : ['missing-pid']),
        ...(healthResult.ok ? [] : ['health-failed']),
        ...healthAudit.failures.map((row) => row.code)
      ]
    });
  }
  const frozenCodeOk = !checkCode || actualCodeHash === loaded.manifest.frozenCodeHash;
  const report = {
    ok: loaded.ok && routePlanAudit.ok && frozenCodeOk
      && rows.every((row) => row.failures.length === 0),
    manifest: loaded.file,
    manifestHash: loaded.hash,
    topologyId: loaded.manifest.topologyId,
    frozenCodeHash: loaded.manifest.frozenCodeHash,
    actualCodeHash,
    frozenCodeOk,
    routePlan: routePlan ? {
      file: routePlanFile,
      hash: routePlan.hash || '',
      fileSha256: routePlanFileHash,
      expectedFileSha256: expectedRoutePlanFileHash,
      fileSha256Ok: routePlanFileOk,
      topologyId: routePlan.topologyId || '',
      requiredMode: requireRouteEnforced
        ? 'enforced'
        : requireRouteDormant
          ? 'dormant'
          : 'any',
      ok: routePlanAudit.ok,
      failures: routePlanAudit.failures
    } : null,
    manifestFailures: loaded.failures,
    shards: rows,
    generatedAt: new Date().toISOString()
  };
  console.log(JSON.stringify(report, null, 2));
  if (!report.ok) process.exitCode = 1;
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
