'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const {
  READY_CHECKLIST,
  ShardMaintenanceStore
} = require('../lib/shard-maintenance');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-maintenance-executor-'));
const file = path.join(root, 'state.json');
const tool = path.resolve(__dirname, '..', 'tools', 'shard-maintenance-executor.js');
const actor = { id: 'ops_test', username: 'operator', name: '测试运维', role: 'super' };
const candidateCodeSha256 = 'a'.repeat(64);
const capacityReport = {
  readOnly: true,
  ok: true,
  input: {
    collectedAt: new Date().toISOString(),
    shards: Array.from({ length: 7 }, (_, id) => ({
      id,
      pid: 2000 + id,
      rssBytes: 300 * 1024 * 1024,
      fdCount: 800
    }))
  },
  audit: {
    ok: true,
    fingerprint: 'f'.repeat(64),
    failures: []
  },
  failures: []
};

function run(args) {
  const result = spawnSync(process.execPath, [tool].concat(args), {
    encoding: 'utf8',
    windowsHide: true
  });
  assert.strictEqual(result.status, 0, result.stderr || result.stdout);
  return JSON.parse(result.stdout);
}

try {
  const store = new ShardMaintenanceStore(file, { id: () => 'rollout-cli' });
  const created = store.create({
    phase: 'dormant',
    candidateCommit: 'd587f395',
    candidateCodeSha256,
    artifactPath: '/opt/xingyan-mainline/releases/candidate',
    backupRoot: '/opt/xingyan-mainline/backups/candidate'
  }, actor);
  store.transition(created.id, 'ready', {
    checklist: Object.fromEntries(READY_CHECKLIST.map((key) => [key, true])),
    confirmation: '只逐片发布',
    capacityReport
  }, actor);
  store.transition(created.id, 'deploy', {}, actor);

  let result = run(['--file=' + file, '--status']);
  assert.strictEqual(result.executorActionRequired, true);
  assert.strictEqual(result.rollout.status, 'awaiting_execution');

  result = run(['--file=' + file, '--claim', '--id=rollout-cli', '--shard=0']);
  assert.strictEqual(result.rollout.status, 'deploying');
  assert.strictEqual(result.rollout.shards[0].status, 'deploying');

  result = run([
    '--file=' + file,
    '--complete',
    '--id=rollout-cli',
    '--shard=0',
    '--after-code-sha256=' + candidateCodeSha256,
    '--after-pid=43210'
  ]);
  assert.strictEqual(result.rollout.status, 'awaiting_health');
  assert.strictEqual(result.rollout.shards[0].status, 'deployed');
  assert.strictEqual(result.rollout.shards[0].executionResult.afterPid, 43210);
  assert.strictEqual(result.rollout.shards[1].status, 'pending');

  console.log('shard-maintenance-executor: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
