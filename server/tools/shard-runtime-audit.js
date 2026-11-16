'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { loadManifest } = require('../lib/shard-runtime-manifest');

const ROOT = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
const manifestArg = args.find((value) => value.startsWith('--manifest='));
const topologyArg = args.find((value) => value.startsWith('--topology='));
const manifestFile = manifestArg
  ? path.resolve(manifestArg.slice('--manifest='.length))
  : path.join(ROOT, 'shard-runtime-production.json');
const topologyFile = topologyArg
  ? path.resolve(topologyArg.slice('--topology='.length))
  : path.join(ROOT, 'shard-topologies.json');
const checkSystemd = !args.includes('--no-systemd');
const checkCode = !args.includes('--no-code');
const loaded = loadManifest(manifestFile, { topologyFile });

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
    rows.push({
      id: shard.id,
      service: shard.service,
      backendPort: shard.backendPort,
      state: active.value,
      pid: pid.value,
      health: healthResult,
      failures: [
        ...(active.ok && active.value === 'active' ? [] : ['service-not-active']),
        ...(pid.ok && Number(pid.value) > 0 ? [] : ['missing-pid']),
        ...(healthResult.ok ? [] : ['health-failed'])
      ]
    });
  }
  const frozenCodeOk = !checkCode || actualCodeHash === loaded.manifest.frozenCodeHash;
  const report = {
    ok: loaded.ok && frozenCodeOk && rows.every((row) => row.failures.length === 0),
    manifest: loaded.file,
    manifestHash: loaded.hash,
    topologyId: loaded.manifest.topologyId,
    frozenCodeHash: loaded.manifest.frozenCodeHash,
    actualCodeHash,
    frozenCodeOk,
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
