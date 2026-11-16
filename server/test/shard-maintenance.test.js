'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const {
  FROZEN_TARGET,
  READY_CHECKLIST,
  createRollout,
  markReady,
  deployCurrent,
  claimCurrent,
  completeCurrent,
  failExecution,
  reportHealth,
  approveNext,
  rollback,
  ShardMaintenanceStore
} = require('../lib/shard-maintenance');

const actor = {
  id: 'ops_test',
  username: 'operator',
  name: '测试运维',
  role: 'super'
};
const input = {
  phase: 'dormant',
  candidateCommit: 'd80705dc9b7b77149fa2575ec0d450d63171693a',
  candidateCodeSha256: 'a'.repeat(64),
  artifactPath: '/opt/xingyan-mainline/releases/candidate',
  backupRoot: '/opt/xingyan-mainline/backups/candidate'
};
const clock = (() => {
  let tick = 0;
  return () => new Date(Date.UTC(2026, 10, 17, 0, 0, tick++)).toISOString();
})();

let rollout = createRollout(input, { now: clock(), id: 'rollout-test', actor });
assert.strictEqual(rollout.status, 'draft');
assert.strictEqual(rollout.shards.length, 7);
assert.strictEqual(new Set(rollout.shards.map((row) => row.backendPort)).size, 7);
assert.throws(() => markReady(rollout, {
  checklist: {},
  confirmation: '只逐片发布'
}, { now: clock(), actor }), /发布前检查未完成/);

const checklist = Object.fromEntries(READY_CHECKLIST.map((key) => [key, true]));
markReady(rollout, { checklist, confirmation: '只逐片发布' }, { now: clock(), actor });
assert.strictEqual(rollout.status, 'ready');
deployCurrent(rollout, { now: clock(), actor });
assert.strictEqual(rollout.status, 'awaiting_execution');
assert.strictEqual(rollout.currentShard, 0);
assert.strictEqual(rollout.shards[0].status, 'queued');
assert.throws(() => reportHealth(rollout, {
  shardId: 0,
  ok: false,
  evidence: {}
}, { now: clock(), actor }), /还没有进入等待验收状态/);

claimCurrent(rollout, { shardId: 0 }, { now: clock(), actor });
assert.strictEqual(rollout.status, 'deploying');
assert.strictEqual(rollout.shards[0].status, 'deploying');
assert.throws(() => completeCurrent(rollout, {
  shardId: 0,
  afterCodeSha256: 'b'.repeat(64),
  afterPid: 1234,
  systemdActive: true
}, { now: clock(), actor }), /代码哈希与候选不一致/);
completeCurrent(rollout, {
  shardId: 0,
  afterCodeSha256: input.candidateCodeSha256,
  afterPid: 1234,
  systemdActive: true
}, { now: clock(), actor });
assert.strictEqual(rollout.status, 'awaiting_health');
assert.strictEqual(rollout.shards[0].status, 'deployed');

const evidence = {
  shardId: 0,
  service: FROZEN_TARGET.shards[0].service,
  backendPort: FROZEN_TARGET.shards[0].backendPort,
  runtimeManifestHash: FROZEN_TARGET.runtimeManifestHash,
  runtimeTopologyId: FROZEN_TARGET.topologyId,
  chatRoutePlanHash: FROZEN_TARGET.routePlanHash,
  chatRoutePlanFileHash: FROZEN_TARGET.routePlanFileSha256,
  chatRoutePlanEnforced: false
};
assert.throws(() => reportHealth(rollout, {
  shardId: 1,
  ok: true,
  evidence
}, { now: clock(), actor }), /只能验收当前分片/);
assert.throws(() => reportHealth(rollout, {
  shardId: 0,
  ok: true,
  evidence: Object.assign({}, evidence, { chatRoutePlanFileHash: 'b'.repeat(64) })
}, { now: clock(), actor }), /健康证据与冻结点不一致/);

reportHealth(rollout, { shardId: 0, ok: true, evidence }, { now: clock(), actor });
assert.strictEqual(rollout.status, 'awaiting_approval');
assert.strictEqual(rollout.shards[0].status, 'healthy');
assert.throws(() => deployCurrent(rollout, { now: clock(), actor }), /当前不在可发布状态/);
assert.throws(() => approveNext(rollout, {
  confirmation: '确认错误'
}, { now: clock(), actor }), /确认口令/);

approveNext(rollout, { confirmation: '确认第0片健康' }, { now: clock(), actor });
assert.strictEqual(rollout.status, 'ready');
assert.strictEqual(rollout.currentShard, 1);
assert.strictEqual(rollout.shards[1].status, 'pending');
assert.strictEqual(rollout.shards[2].status, 'pending');

deployCurrent(rollout, { now: clock(), actor });
claimCurrent(rollout, { shardId: 1 }, { now: clock(), actor });
failExecution(rollout, {
  shardId: 1,
  reason: '健康接口超时'
}, { now: clock(), actor });
assert.strictEqual(rollout.status, 'paused');
assert.strictEqual(rollout.shards[1].status, 'failed');
assert.throws(() => approveNext(rollout, {
  confirmation: '确认第1片健康'
}, { now: clock(), actor }), /健康通过/);
rollback(rollout, { confirmation: '停止并回滚', reason: '测试回滚' }, {
  now: clock(),
  actor
});
assert.strictEqual(rollout.status, 'rolled_back');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-shard-maintenance-'));
try {
  const file = path.join(root, 'shard-maintenance.json');
  const store = new ShardMaintenanceStore(file, {
    now: clock,
    id: (() => {
      let index = 0;
      return () => 'maintenance-' + (++index);
    })()
  });
  const created = store.create(input, actor);
  assert.strictEqual(created.id, 'maintenance-1');
  assert.throws(() => store.create(input, actor), /已有未结束的发布/);
  fs.writeFileSync(file + '.lock', JSON.stringify({ pid: process.pid }));
  assert.throws(() => store.transition(created.id, 'ready', {
    checklist,
    confirmation: '只逐片发布'
  }, actor), /另一个维护操作正在执行/);
  fs.unlinkSync(file + '.lock');
  store.transition(created.id, 'ready', {
    checklist,
    confirmation: '只逐片发布'
  }, actor);
  const reloaded = new ShardMaintenanceStore(file);
  assert.strictEqual(reloaded.list()[0].status, 'ready');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}

console.log('shard-maintenance: passed');
