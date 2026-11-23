#!/usr/bin/env node
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const PLAN_FILE = String(process.env.FLEET_PLAN_FILE
  || '/etc/xingyan-dual-cell/current-fleet.json');
const LOCAL_CELL_ID = String(process.env.LOCAL_CELL_ID || '');
const SSH_KEY = String(process.env.SSH_KEY || '/root/.ssh/xingyan-cluster');
const SSH_USER = String(process.env.SSH_USER || 'root');
const STATUS_FILE = String(process.env.SYNC_STATUS_FILE
  || '/run/xingyan-fleet-replication/status.json');
const INTERVAL_MS = Math.max(1000, Number(process.env.SYNC_INTERVAL_MS) || 5000);

function atomicJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temporary = file + '.' + process.pid + '.tmp';
  fs.writeFileSync(temporary, JSON.stringify(value, null, 2) + '\n');
  fs.renameSync(temporary, file);
}

function run(argv, timeoutMs) {
  return new Promise((resolve, reject) => {
    const child = spawn(argv[0], argv.slice(1), {
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });
    const err = [];
    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      reject(new Error('replication command timeout'));
    }, timeoutMs || 60 * 60 * 1000);
    child.stderr.on('data', (chunk) => err.push(chunk));
    child.on('error', reject);
    child.on('close', (code) => {
      clearTimeout(timer);
      if (code !== 0) {
        reject(new Error(Buffer.concat(err).toString('utf8').slice(0, 4000)));
      } else {
        resolve();
      }
    });
  });
}

function loadPlan() {
  const bytes = fs.readFileSync(PLAN_FILE);
  const plan = JSON.parse(bytes.toString('utf8'));
  if (!plan || plan.version !== 1 || !Array.isArray(plan.cells)) {
    throw new Error('invalid fleet plan');
  }
  return {
    plan,
    sha256: crypto.createHash('sha256').update(bytes).digest('hex')
  };
}

async function syncOnce() {
  const { plan, sha256 } = loadPlan();
  const local = plan.cells.find((cell) => cell.id === LOCAL_CELL_ID);
  if (!local) throw new Error('local cell is not present in fleet plan');
  const startedAt = new Date().toISOString();
  const rows = [];
  for (const shard of local.ownerShards || []) {
    const source = path.join(local.dataRoot, String(shard)) + '/';
    const replicas = plan.cells.filter((cell) =>
      cell.id !== local.id && (cell.replicaShards || []).includes(shard));
    for (const replica of replicas) {
      const target = path.join(replica.dataRoot, String(shard)) + '/';
      try {
        await run(['rsync', '-aH', '--checksum', '--delete-delay',
          '--exclude=*.tmp', '--exclude=*.part',
          '--exclude=metrics-history.jsonl',
          '-e', 'ssh -i ' + SSH_KEY
            + ' -o BatchMode=yes -o StrictHostKeyChecking=accept-new',
          source, SSH_USER + '@' + replica.host + ':' + target]);
        rows.push({ shard, replica: replica.id, ok: true });
      } catch (error) {
        rows.push({
          shard,
          replica: replica.id,
          ok: false,
          error: String(error && error.message || error)
        });
      }
    }
  }
  const result = {
    version: 1,
    startedAt,
    finishedAt: new Date().toISOString(),
    planSha256: sha256,
    topologyId: String(plan.topologyId || ''),
    localCellId: local.id,
    ok: rows.every((row) => row.ok),
    rows
  };
  atomicJson(STATUS_FILE, result);
  return result;
}

async function main() {
  if (!LOCAL_CELL_ID) throw new Error('LOCAL_CELL_ID is required');
  if (process.argv.includes('--once')) {
    const result = await syncOnce();
    process.stdout.write(JSON.stringify(result) + '\n');
    if (!result.ok) process.exitCode = 2;
    return;
  }
  let stopping = false;
  process.on('SIGTERM', () => { stopping = true; });
  process.on('SIGINT', () => { stopping = true; });
  while (!stopping) {
    try {
      await syncOnce();
    } catch (error) {
      atomicJson(STATUS_FILE, {
        version: 1,
        updatedAt: new Date().toISOString(),
        ok: false,
        error: String(error && error.message || error)
      });
    }
    await new Promise((resolve) => setTimeout(resolve, INTERVAL_MS));
  }
}

main().catch((error) => {
  process.stderr.write(String(error && error.stack || error) + '\n');
  process.exitCode = 1;
});
