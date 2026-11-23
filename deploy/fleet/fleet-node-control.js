#!/usr/bin/env node
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

function loadProvisionModule() {
  const candidates = [
    path.resolve(__dirname, '../../lib/fleet-node-provision'),
    path.resolve(__dirname, '../../server/lib/fleet-node-provision')
  ];
  for (const candidate of candidates) {
    try { return require(candidate); }
    catch (error) {
      if (!error || error.code !== 'MODULE_NOT_FOUND') throw error;
    }
  }
  throw new Error('fleet-node-provision module is missing');
}

function fail(message) {
  throw new Error(String(message || 'fleet-node-control failed'));
}

function safeAbsolute(value, label) {
  const out = String(value || '').trim();
  if (!out.startsWith('/') || out.split('/').includes('..')) {
    fail(label + ' must be an absolute safe path');
  }
  return out;
}

function positive(value, label) {
  const out = Number(value);
  if (!Number.isInteger(out) || out <= 0) fail(label + ' must be positive');
  return out;
}

function run(argv, timeoutMs) {
  return new Promise((resolve, reject) => {
    const child = spawn(argv[0], argv.slice(1), {
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });
    const stdout = [];
    const stderr = [];
    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      reject(new Error('command timeout: ' + path.basename(argv[0])));
    }, Math.max(5000, Number(timeoutMs) || 300000));
    child.stdout.on('data', (chunk) => stdout.push(chunk));
    child.stderr.on('data', (chunk) => stderr.push(chunk));
    child.on('error', reject);
    child.on('close', (code) => {
      clearTimeout(timer);
      const out = Buffer.concat(stdout).toString('utf8').trim();
      const err = Buffer.concat(stderr).toString('utf8').trim();
      if (code !== 0) {
        reject(new Error((err || out || 'command failed').slice(0, 4000)));
        return;
      }
      resolve(out);
    });
  });
}

async function manifest(root) {
  const rows = [];
  const walk = async (dir, relative) => {
    const names = fs.readdirSync(dir).sort();
    for (const name of names) {
      if (name.endsWith('.tmp') || name.endsWith('.part')
          || name === 'metrics-history.jsonl') continue;
      const full = path.join(dir, name);
      const rel = relative ? relative + '/' + name : name;
      const stat = fs.lstatSync(full);
      if (stat.isDirectory()) {
        await walk(full, rel);
      } else if (stat.isFile()) {
        const hash = crypto.createHash('sha256')
          .update(fs.readFileSync(full))
          .digest('hex');
        rows.push({ path: rel, size: stat.size, sha256: hash });
      }
    }
  };
  await walk(root, '');
  return {
    files: rows.length,
    bytes: rows.reduce((sum, row) => sum + row.size, 0),
    hash: crypto.createHash('sha256').update(JSON.stringify(rows)).digest('hex')
  };
}

async function planInfo(file) {
  const bytes = fs.readFileSync(file);
  const plan = JSON.parse(bytes.toString('utf8'));
  return {
    plan,
    hash: String(plan.hash || ''),
    fileSha256: crypto.createHash('sha256').update(bytes).digest('hex')
  };
}

async function shardSignal(port, endpoint, planFile, secretFile, body) {
  const info = await planInfo(planFile);
  const secret = fs.readFileSync(secretFile, 'utf8').trim();
  if (!secret) fail('relay secret is empty');
  const response = await fetch('http://127.0.0.1:' + port + endpoint, {
    method: 'POST',
    signal: AbortSignal.timeout(5000),
    headers: {
      'Content-Type': 'application/json',
      'X-Shard-Relay': secret
    },
    body: JSON.stringify(Object.assign({
      planHash: info.hash,
      fileSha256: info.fileSha256
    }, body))
  });
  const payload = await response.json();
  if (!response.ok || !payload || payload.ok !== true) {
    fail(payload && payload.error || 'shard signal failed');
  }
  return payload.data;
}

async function health(port, expectedPlanHash, expectedFileSha256) {
  const response = await fetch('http://127.0.0.1:' + port + '/api/health', {
    signal: AbortSignal.timeout(5000)
  });
  const payload = await response.json();
  const data = payload && payload.data;
  if (!response.ok || !payload || payload.ok !== true || !data) fail('health failed');
  if (expectedPlanHash && data.chatRoutePlanHash !== expectedPlanHash) {
    fail('route plan hash mismatch');
  }
  if (expectedFileSha256 && data.chatRoutePlanFileHash !== expectedFileSha256) {
    fail('route plan file hash mismatch');
  }
  return data;
}

async function prepare(payload) {
  const root = safeAbsolute(payload.dataRoot, 'dataRoot');
  fs.mkdirSync(root, { recursive: true });
  fs.accessSync(root, fs.constants.R_OK | fs.constants.W_OK);
  const stats = fs.statfsSync(root);
  const freeBytes = Number(stats.bsize) * Number(stats.bavail);
  const freeInodes = Number(stats.ffree);
  if (freeBytes < Number(payload.minimumFreeBytes || 0)) fail('insufficient disk');
  if (freeInodes < Number(payload.minimumFreeInodes || 0)) fail('insufficient inodes');
  const ports = (payload.ports || []).map((value) =>
    positive(value, 'port'));
  const results = [];
  for (let shard = 0; shard < Number(payload.shardCount); shard += 1) {
    const service = String(payload.servicePrefix) + '@' + shard + '.service';
    await run(['systemctl', 'cat', service], 10000);
    const row = await health(ports[shard]);
    results.push({ shard, service, port: ports[shard], pid: row.pid || 0 });
  }
  return { ok: true, root, freeBytes, freeInodes, shards: results };
}

async function provision(payload) {
  const plan = loadProvisionModule().buildNodeProvisionPlan(payload);
  const sourceUser = String(payload.sourceUser || 'root');
  if (!/^[a-z_][a-z0-9_-]*$/i.test(sourceUser)) fail('invalid source user');
  const sourceHost = String(plan.sourceHost || '');
  if (!/^(?:\d{1,3}\.){3}\d{1,3}$/.test(sourceHost)
      && !/^[a-z0-9][a-z0-9.-]*$/i.test(sourceHost)) {
    fail('invalid source host');
  }
  const clusterKeyFile = safeAbsolute(payload.clusterKeyFile
    || '/root/.ssh/xingyan-cluster', 'clusterKeyFile');
  if (!fs.existsSync(clusterKeyFile)) fail('cluster SSH key is missing');
  fs.mkdirSync(plan.dataRoot, { recursive: true });
  const stats = fs.statfsSync(plan.dataRoot);
  const freeBytes = Number(stats.bsize) * Number(stats.bavail);
  const freeInodes = Number(stats.ffree);
  if (freeBytes < Number(payload.minimumFreeBytes || 0)) fail('insufficient disk');
  if (freeInodes < Number(payload.minimumFreeInodes || 0)) fail('insufficient inodes');
  fs.mkdirSync(path.dirname(plan.envFile), { recursive: true });
  fs.mkdirSync(path.dirname(plan.unitFile), { recursive: true });
  fs.mkdirSync(plan.releaseRoot, { recursive: true });
  const launcher = path.join(plan.releaseRoot, 'run-dual-cell-shard.sh');
  const sshCommand = 'ssh -i ' + clusterKeyFile
    + ' -o BatchMode=yes -o StrictHostKeyChecking=accept-new';
  if (!fs.existsSync(launcher)) {
    await run([
      'rsync', '-aH', '--checksum', '--delete-delay',
      '--exclude=*.tmp', '--exclude=*.part',
      '-e', sshCommand,
      sourceUser + '@' + sourceHost + ':' + plan.sourceRoot + '/',
      plan.releaseRoot + '/'
    ], 30 * 60 * 1000);
  }
  if (!fs.existsSync(launcher)) fail('release launcher is missing after bootstrap');
  const copySeedFile = async (source, target, mode) => {
    if (fs.existsSync(target)) return;
    fs.mkdirSync(path.dirname(target), { recursive: true });
    await run([
      'scp', '-q', '-i', clusterKeyFile,
      '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new',
      sourceUser + '@' + sourceHost + ':' + source,
      target
    ], 5 * 60 * 1000);
    fs.chmodSync(target, mode);
  };
  await copySeedFile(plan.routeSourceFile, plan.routePlan, 0o600);
  await copySeedFile(plan.secretSourceFile, plan.secretFile, 0o600);
  const routeSha = crypto.createHash('sha256')
    .update(fs.readFileSync(plan.routePlan))
    .digest('hex');
  if (payload.routePlanSha256
      && routeSha !== String(payload.routePlanSha256).toLowerCase()) {
    fail('route plan hash mismatch after bootstrap');
  }
  if (payload.fleetPlanContentBase64) {
    const bytes = Buffer.from(String(payload.fleetPlanContentBase64), 'base64');
    const actual = crypto.createHash('sha256').update(bytes).digest('hex');
    if (payload.fleetPlanSha256
        && actual !== String(payload.fleetPlanSha256).toLowerCase()) {
      fail('fleet plan hash mismatch');
    }
    const value = JSON.parse(bytes.toString('utf8'));
    if (!value || value.version !== 1 || !Array.isArray(value.cells)) {
      fail('invalid bootstrap fleet plan');
    }
    writeAtomic(plan.fleetPlan, bytes, 0o600);
  } else if (!fs.existsSync(plan.fleetPlan)) {
    fail('bootstrap fleet plan is required');
  }
  writeAtomic(plan.envFile, plan.env, 0o600);
  writeAtomic(plan.unitFile, plan.unit, 0o644);
  await run(['systemctl', 'daemon-reload'], 30000);
  const services = [];
  for (let shard = 0; shard < plan.shardCount; shard += 1) {
    const service = plan.servicePrefix + '@' + shard + '.service';
    await run(['systemctl', 'enable', '--now', service], 120000);
    const port = Number(payload.ports[shard]);
    const health = await health(port);
    services.push({ shard, service, port, pid: health.pid || 0 });
  }
  return {
    ok: true,
    cellId: plan.cellId,
    fingerprint: plan.fingerprint,
    releaseRoot: plan.releaseRoot,
    dataRoot: plan.dataRoot,
    envFile: plan.envFile,
    unitFile: plan.unitFile,
    services
  };
}

async function decommission(payload) {
  const servicePrefix = safeName(payload.servicePrefix, 'servicePrefix');
  const cellId = safeName(payload.cellId, 'cellId');
  const dataRoot = safeAbsolute(payload.dataRoot, 'dataRoot');
  const fleetPlan = safeAbsolute(payload.fleetPlan, 'fleetPlan');
  const shardCount = positive(payload.shardCount, 'shardCount');
  if (fs.existsSync(fleetPlan)) {
    const plan = JSON.parse(fs.readFileSync(fleetPlan, 'utf8'));
    const cell = (plan.cells || []).find((row) => row.id === cellId);
    if (cell && Array.isArray(cell.ownerShards) && cell.ownerShards.length) {
      fail('cell still owns shards and cannot be decommissioned');
    }
  }
  const services = [];
  for (let shard = shardCount - 1; shard >= 0; shard -= 1) {
    const service = servicePrefix + '@' + shard + '.service';
    await run(['systemctl', 'stop', service], 120000);
    await run(['systemctl', 'disable', service], 120000);
    services.push({ shard, service, stopped: true });
  }
  const marker = path.join(dataRoot, '.decommissioned', cellId + '.json');
  writeAtomic(marker, JSON.stringify({
    version: 1,
    cellId,
    servicePrefix,
    dataRoot,
    decommissionedAt: new Date().toISOString(),
    services
  }, null, 2) + '\n', 0o600);
  return {
    ok: true,
    cellId,
    marker,
    dataPreserved: true,
    services
  };
}

function writeAtomic(file, content, mode) {
  const temporary = file + '.fleet-' + process.pid + '.tmp';
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(temporary, content, { encoding: 'utf8', mode: mode || 0o600 });
  fs.renameSync(temporary, file);
}

async function writeGatewayEnv(payload) {
  const file = safeAbsolute(payload.path, 'gateway env path');
  const current = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
  const lines = current.split(/\r?\n/);
  const values = payload.values && typeof payload.values === 'object'
    ? payload.values : {};
  for (const [key, value] of Object.entries(values)) {
    if (!/^[A-Z][A-Z0-9_]*$/.test(key)) fail('unsafe env key: ' + key);
    if (/[\r\n]/.test(String(value))) fail('env value contains newline');
  }
  const output = [];
  const seen = new Set();
  for (const line of lines) {
    const match = /^([A-Z][A-Z0-9_]*)=/.exec(line);
    if (match && Object.prototype.hasOwnProperty.call(values, match[1])) {
      output.push(match[1] + '=' + values[match[1]]);
      seen.add(match[1]);
    } else {
      output.push(line);
    }
  }
  for (const [key, value] of Object.entries(values)) {
    if (!seen.has(key)) output.push(key + '=' + value);
  }
  writeAtomic(file, output.filter((line, index, all) =>
    line || index < all.length - 1).join('\n') + '\n', 0o600);
  return { ok: true, path: file, fingerprint: crypto.createHash('sha256')
    .update(fs.readFileSync(file)).digest('hex') };
}

async function writeGatewayRouting(payload) {
  const file = safeAbsolute(payload.path, 'gateway routing path');
  const ownerPorts = (payload.ownerPorts || []).map((value) =>
    positive(value, 'owner port'));
  const ownerTargets = (payload.ownerTargets || []).map((value) => {
    const url = new URL(String(value));
    if (!['http:', 'https:'].includes(url.protocol)
        || !url.hostname || !url.port || url.pathname !== '/'
        || url.username || url.password || url.search || url.hash) {
      fail('invalid owner target');
    }
    return url.origin;
  });
  if (ownerTargets.length !== ownerPorts.length) fail('owner target count mismatch');
  const content = JSON.stringify({
    version: 1,
    ownerPorts,
    ownerTargets,
    routePlanHash: String(payload.routePlanHash || ''),
    updatedAt: new Date().toISOString()
  }) + '\n';
  writeAtomic(file, content, 0o600);
  return {
    ok: true,
    path: file,
    ownerPorts,
    ownerTargets,
    fingerprint: crypto.createHash('sha256').update(content).digest('hex')
  };
}

async function writeFleetPlan(payload) {
  const file = safeAbsolute(payload.path, 'fleet plan path');
  const bytes = Buffer.from(String(payload.contentBase64 || ''), 'base64');
  const sha256 = crypto.createHash('sha256').update(bytes).digest('hex');
  if (sha256 !== String(payload.sha256 || '').toLowerCase()) {
    fail('fleet plan hash mismatch');
  }
  const plan = JSON.parse(bytes.toString('utf8'));
  if (!plan || plan.version !== 1 || !Array.isArray(plan.cells)) {
    fail('invalid fleet plan');
  }
  for (let shard = 0; shard < Number(plan.shardCount); shard += 1) {
    const owners = plan.cells.filter((cell) =>
      Array.isArray(cell.ownerShards) && cell.ownerShards.includes(shard));
    if (owners.length !== 1) fail('shard must have exactly one owner: ' + shard);
  }
  writeAtomic(file, bytes, 0o600);
  return {
    ok: true,
    path: file,
    sha256,
    topologyId: String(plan.topologyId || '')
  };
}

async function main() {
  const action = String(process.argv[2] || '');
  const payload = JSON.parse(Buffer.from(String(process.argv[3] || ''), 'base64')
    .toString('utf8') || '{}');
  let result;
  switch (action) {
    case 'prepare':
      result = await prepare(payload);
      break;
    case 'provision':
      result = await provision(payload);
      break;
    case 'decommission':
      result = await decommission(payload);
      break;
    case 'manifest': {
      const root = safeAbsolute(payload.root, 'root');
      result = Object.assign({ ok: true, root }, await manifest(root));
      break;
    }
    case 'replicate': {
      const sourceRoot = safeAbsolute(payload.sourceRoot, 'sourceRoot');
      const targetRoot = safeAbsolute(payload.targetRoot, 'targetRoot');
      const sourceHost = String(payload.sourceHost || '').trim();
      const sourceUser = String(payload.sourceUser || 'root').trim();
      if (!/^(?:\d{1,3}\.){3}\d{1,3}$/.test(sourceHost)
          && !/^[a-z0-9][a-z0-9.-]*$/i.test(sourceHost)) fail('invalid source host');
      if (!/^[a-z_][a-z0-9_-]*$/i.test(sourceUser)) fail('invalid source user');
      fs.mkdirSync(targetRoot, { recursive: true });
      await run(['rsync', '-aH', '--checksum', '--delete-delay',
        '--exclude=*.tmp', '--exclude=*.part',
        '--exclude=metrics-history.jsonl',
        '-e', 'ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new',
        sourceUser + '@' + sourceHost + ':' + sourceRoot + '/',
        targetRoot + '/'], 6 * 60 * 60 * 1000);
      result = Object.assign({ ok: true, sourceRoot, targetRoot }, await manifest(targetRoot));
      break;
    }
    case 'freeze-one':
    case 'unfreeze-one': {
      const data = await shardSignal(positive(payload.port, 'port'),
        '/__shard/write-freeze', payload.planFile, payload.secretFile, {
          frozen: action === 'freeze-one',
          epoch: Date.now(),
          reason: action === 'freeze-one' ? String(payload.reason || 'physical-scale') : ''
        });
      result = Object.assign({ ok: true }, data);
      break;
    }
    case 'owner-one': {
      const enabled = payload.enable === true;
      const data = await shardSignal(positive(payload.port, 'port'),
        '/__shard/owner-routing', payload.planFile, payload.secretFile, {
          enabled
        });
      result = Object.assign({ ok: true }, data);
      break;
    }
    case 'health-one':
      result = Object.assign({ ok: true }, await health(
        positive(payload.port, 'port'),
        payload.expectedPlanHash,
        payload.expectedFileSha256
      ));
      break;
    case 'verify-one': {
      const status = await health(positive(payload.port, 'port'),
        payload.expectedPlanHash, payload.expectedFileSha256);
      if (payload.expectedOwnerCell
          && status.chatRoutePlanEnforced !== true) fail('owner routing not enforced');
      result = { ok: true, status };
      break;
    }
    case 'write-gateway-routing':
      result = await writeGatewayRouting(payload);
      break;
    case 'write-fleet-plan':
      result = await writeFleetPlan(payload);
      break;
    case 'write-gateway-env':
      result = await writeGatewayEnv(payload);
      break;
    case 'reload-gateway': {
      const service = String(payload.service || '');
      if (!/^[a-z0-9_.@-]+$/i.test(service)) fail('invalid service');
      await run(['systemctl', 'kill', '--signal=HUP', service], 30000);
      const status = await health(
        positive(payload.port, 'port'),
        payload.expectedPlanHash,
        payload.expectedFileSha256
      );
      result = { ok: true, service, reloadMode: 'SIGHUP', status };
      break;
    }
    case 'restart': {
      const service = String(payload.service || '');
      if (!/^[a-z0-9_.@-]+$/i.test(service)) fail('invalid service');
      await run(['systemctl', 'restart', service], 120000);
      const port = positive(payload.port, 'port');
      const status = await health(port, payload.expectedPlanHash,
        payload.expectedFileSha256);
      result = { ok: true, service, status };
      break;
    }
    default:
      fail('unsupported action: ' + action);
  }
  process.stdout.write(JSON.stringify(result) + '\n');
}

main().catch((error) => {
  process.stderr.write(String(error && error.stack || error) + '\n');
  process.exitCode = 1;
});
