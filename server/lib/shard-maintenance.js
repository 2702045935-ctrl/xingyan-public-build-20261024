'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const FROZEN_TARGET = Object.freeze({
  topologyId: 'server-b-mainline-shards-7',
  runtimeManifestHash: 'f7afcdef3bd1d51ef7b50f58650009693397686faaaa31da6738ed96aa4f0f44',
  stableCodeSha256: 'cb937047456b6c6bf4aa1b174b4d1edb397e54c1e47ff60f6ca0341b4215007c',
  routePlanHash: '839c5a4e64e7aa4feb43d49a71de5eb017b0f93918bd05dbacb215dab02da660',
  routePlanFileSha256: 'c02d3ccb14304371044aad4096cc9501d072566c232fb51700d8e228e68d519c',
  shards: [
    { id: 0, service: 'xingyan-mainline-shard@0.service', backendPort: 7080, entryPort: 15299 },
    { id: 1, service: 'xingyan-mainline-shard@1.service', backendPort: 7180, entryPort: 15399 },
    { id: 2, service: 'xingyan-mainline-shard@2.service', backendPort: 7280, entryPort: 15499 },
    { id: 3, service: 'xingyan-mainline-shard@3.service', backendPort: 7380, entryPort: 15599 },
    { id: 4, service: 'xingyan-mainline-shard@4.service', backendPort: 7480, entryPort: 15699 },
    { id: 5, service: 'xingyan-mainline-shard@5.service', backendPort: 7580, entryPort: 15799 },
    { id: 6, service: 'xingyan-mainline-shard@6.service', backendPort: 7680, entryPort: 15899 }
  ]
});

const READY_CHECKLIST = [
  'artifactVerified',
  'backupVerified',
  'routePlanVerified',
  'sevenShardPreflight',
  'maintenanceWindowConfirmed'
];

const TERMINAL_STATES = new Set(['completed', 'rolled_back']);

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function hash(value) {
  return crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
}

function isHash(value) {
  return /^[a-f0-9]{64}$/i.test(String(value || ''));
}

function text(value, max) {
  return String(value == null ? '' : value).trim().slice(0, max || 500);
}

function actorOf(actor) {
  const source = actor || {};
  return {
    id: text(source.id, 80),
    username: text(source.username, 80),
    name: text(source.name, 80),
    role: text(source.role, 30)
  };
}

function appendEvent(rollout, type, actor, at, detail) {
  rollout.events.push({
    at,
    type,
    actor: actorOf(actor),
    shardId: rollout.currentShard,
    detail: detail || {}
  });
}

function assertTarget(payload) {
  if (payload.topologyId !== FROZEN_TARGET.topologyId
      || payload.runtimeManifestHash !== FROZEN_TARGET.runtimeManifestHash
      || payload.stableCodeSha256 !== FROZEN_TARGET.stableCodeSha256
      || payload.routePlanHash !== FROZEN_TARGET.routePlanHash
      || payload.routePlanFileSha256 !== FROZEN_TARGET.routePlanFileSha256) {
    throw new Error('发布目标与冻结值不一致');
  }
}

function createRollout(input, options) {
  const body = input || {};
  const opts = options || {};
  const phase = text(body.phase, 20);
  if (phase !== 'dormant' && phase !== 'enforced') {
    throw new Error('发布阶段必须是 dormant 或 enforced');
  }
  assertTarget(FROZEN_TARGET);
  const candidateCodeSha256 = text(body.candidateCodeSha256, 64).toLowerCase();
  if (!isHash(candidateCodeSha256)) throw new Error('候选代码 SHA256 格式不对');
  if (candidateCodeSha256 === FROZEN_TARGET.stableCodeSha256) {
    throw new Error('候选代码与稳定版相同，没有可发布内容');
  }
  const candidateCommit = text(body.candidateCommit, 80);
  const artifactPath = text(body.artifactPath, 400);
  const backupRoot = text(body.backupRoot, 400);
  if (!candidateCommit) throw new Error('候选提交号不能为空');
  if (!artifactPath) throw new Error('候选包绝对路径不能为空');
  if (!backupRoot) throw new Error('回滚目录不能为空');
  if (!path.posix.isAbsolute(artifactPath)) throw new Error('候选包必须是绝对路径');
  if (!path.posix.isAbsolute(backupRoot)) throw new Error('回滚目录必须是绝对路径');

  const at = opts.now || new Date().toISOString();
  const actor = actorOf(opts.actor);
  const rollout = {
    version: 1,
    id: opts.id || crypto.randomUUID(),
    status: 'draft',
    phase,
    currentShard: 0,
    createdAt: at,
    updatedAt: at,
    createdBy: actor,
    candidate: {
      candidateCommit,
      candidateCodeSha256,
      artifactPath,
      backupRoot
    },
    target: clone(FROZEN_TARGET),
    checklist: Object.fromEntries(READY_CHECKLIST.map((key) => [key, false])),
    shards: clone(FROZEN_TARGET.shards).map((shard) => Object.assign(shard, {
      status: 'pending',
      deployedAt: '',
      deployedBy: null,
      health: null,
      approvedAt: '',
      approvedBy: null
    })),
    events: []
  };
  appendEvent(rollout, 'created', actor, at, {
    phase,
    candidateCommit,
    candidateCodeSha256
  });
  return rollout;
}

function markReady(rollout, input, options) {
  const body = input || {};
  const opts = options || {};
  if (rollout.status !== 'draft') throw new Error('只有草稿可以进入待发布状态');
  for (const key of READY_CHECKLIST) {
    if (body.checklist && body.checklist[key] === true) rollout.checklist[key] = true;
    if (rollout.checklist[key] !== true) throw new Error('发布前检查未完成：' + key);
  }
  if (text(body.confirmation, 40) !== '只逐片发布') {
    throw new Error('请输入确认口令「只逐片发布」');
  }
  rollout.status = 'ready';
  rollout.updatedAt = opts.now || new Date().toISOString();
  rollout.readyAt = rollout.updatedAt;
  appendEvent(rollout, 'ready', opts.actor, rollout.updatedAt, {
    checklist: clone(rollout.checklist)
  });
  return rollout;
}

function currentShardOf(rollout) {
  return rollout.shards.find((shard) => shard.id === rollout.currentShard) || null;
}

function deployCurrent(rollout, options) {
  const opts = options || {};
  if (rollout.status !== 'ready') throw new Error('当前不在可发布状态');
  const shard = currentShardOf(rollout);
  if (!shard || shard.status !== 'pending') throw new Error('当前分片状态异常');
  const at = opts.now || new Date().toISOString();
  shard.status = 'queued';
  shard.deployedAt = at;
  shard.deployedBy = actorOf(opts.actor);
  rollout.status = 'awaiting_execution';
  rollout.updatedAt = at;
  appendEvent(rollout, 'execution-requested', opts.actor, at, {
    service: shard.service,
    backendPort: shard.backendPort
  });
  return rollout;
}

function claimCurrent(rollout, input, options) {
  const body = input || {};
  const opts = options || {};
  if (rollout.status !== 'awaiting_execution') {
    throw new Error('当前没有等待执行的分片');
  }
  const shard = currentShardOf(rollout);
  if (Number(body.shardId) !== shard.id || shard.status !== 'queued') {
    throw new Error('执行器只能领取当前排队分片');
  }
  const at = opts.now || new Date().toISOString();
  shard.status = 'deploying';
  shard.executorClaimedAt = at;
  shard.executorClaimedBy = actorOf(opts.actor);
  rollout.status = 'deploying';
  rollout.updatedAt = at;
  appendEvent(rollout, 'execution-claimed', opts.actor, at, {
    service: shard.service
  });
  return rollout;
}

function completeCurrent(rollout, input, options) {
  const body = input || {};
  const opts = options || {};
  if (rollout.status !== 'deploying') {
    throw new Error('当前没有正在执行的分片');
  }
  const shard = currentShardOf(rollout);
  if (Number(body.shardId) !== shard.id || shard.status !== 'deploying') {
    throw new Error('执行回执与当前分片不一致');
  }
  const afterCodeSha256 = text(body.afterCodeSha256, 64).toLowerCase();
  const afterPid = Number(body.afterPid);
  if (afterCodeSha256 !== rollout.candidate.candidateCodeSha256) {
    throw new Error('执行后的代码哈希与候选不一致');
  }
  if (!Number.isInteger(afterPid) || afterPid <= 0) {
    throw new Error('执行后的 PID 无效');
  }
  if (body.systemdActive !== true) {
    throw new Error('执行后服务不是 active');
  }
  const at = opts.now || new Date().toISOString();
  shard.status = 'deployed';
  shard.executionResult = {
    completedAt: at,
    completedBy: actorOf(opts.actor),
    afterCodeSha256,
    afterPid
  };
  rollout.status = 'awaiting_health';
  rollout.updatedAt = at;
  appendEvent(rollout, 'execution-completed', opts.actor, at, {
    afterCodeSha256,
    afterPid
  });
  return rollout;
}

function failExecution(rollout, input, options) {
  const body = input || {};
  const opts = options || {};
  if (rollout.status !== 'deploying') {
    throw new Error('当前没有正在执行的分片');
  }
  const shard = currentShardOf(rollout);
  if (Number(body.shardId) !== shard.id) {
    throw new Error('执行失败回执与当前分片不一致');
  }
  const at = opts.now || new Date().toISOString();
  shard.status = 'failed';
  shard.failure = text(body.reason, 500) || '执行器失败';
  rollout.status = 'paused';
  rollout.updatedAt = at;
  appendEvent(rollout, 'execution-failed', opts.actor, at, {
    reason: shard.failure
  });
  return rollout;
}

function healthMismatch(rollout, shard, evidence) {
  const expectedEnforced = rollout.phase === 'enforced';
  const checks = [
    ['shardId', Number(evidence.shardId) === shard.id],
    ['service', text(evidence.service, 100) === shard.service],
    ['backendPort', Number(evidence.backendPort) === shard.backendPort],
    ['runtimeManifestHash',
      text(evidence.runtimeManifestHash, 64).toLowerCase()
        === rollout.target.runtimeManifestHash],
    ['runtimeTopologyId',
      text(evidence.runtimeTopologyId, 100) === rollout.target.topologyId],
    ['chatRoutePlanHash',
      text(evidence.chatRoutePlanHash, 64).toLowerCase()
        === rollout.target.routePlanHash],
    ['chatRoutePlanFileHash',
      text(evidence.chatRoutePlanFileHash, 64).toLowerCase()
        === rollout.target.routePlanFileSha256],
    ['chatRoutePlanEnforced',
      evidence.chatRoutePlanEnforced === expectedEnforced]
  ];
  if (expectedEnforced) {
    checks.push(['activeCalls', Number(evidence.activeCalls) === 0]);
    checks.push(['ringingCalls', Number(evidence.ringingCalls) === 0]);
  }
  return checks.filter((row) => !row[1]).map((row) => row[0]);
}

function reportHealth(rollout, input, options) {
  const body = input || {};
  const opts = options || {};
  if (rollout.status !== 'awaiting_health') {
    throw new Error('当前分片还没有进入等待验收状态');
  }
  const shard = currentShardOf(rollout);
  if (Number(body.shardId) !== shard.id) throw new Error('只能验收当前分片');
  const at = opts.now || new Date().toISOString();
  const evidence = clone(body.evidence || {});
  const mismatches = body.ok === true ? healthMismatch(rollout, shard, evidence) : [];
  if (body.ok === true && mismatches.length) {
    throw new Error('健康证据与冻结点不一致：' + mismatches.join(', '));
  }
  shard.health = {
    ok: body.ok === true,
    recordedAt: at,
    recordedBy: actorOf(opts.actor),
    mismatches,
    evidenceHash: hash(evidence),
    evidence
  };
  if (body.ok === true) {
    shard.status = 'healthy';
    rollout.status = 'awaiting_approval';
  } else {
    shard.status = 'failed';
    shard.failure = text(body.reason, 500) || '健康检查失败';
    rollout.status = 'paused';
  }
  rollout.updatedAt = at;
  appendEvent(rollout, body.ok === true ? 'health-passed' : 'health-failed',
    opts.actor, at, {
      shardId: shard.id,
      evidenceHash: shard.health.evidenceHash,
      reason: shard.failure || ''
    });
  return rollout;
}

function approveNext(rollout, input, options) {
  const body = input || {};
  const opts = options || {};
  if (rollout.status !== 'awaiting_approval') {
    throw new Error('只有健康通过的分片才能批准继续');
  }
  const shard = currentShardOf(rollout);
  const phrase = '确认第' + shard.id + '片健康';
  if (text(body.confirmation, 40) !== phrase) {
    throw new Error('请输入确认口令「' + phrase + '」');
  }
  const at = opts.now || new Date().toISOString();
  shard.approvedAt = at;
  shard.approvedBy = actorOf(opts.actor);
  appendEvent(rollout, 'approved', opts.actor, at, { shardId: shard.id });
  if (shard.id === rollout.shards.length - 1) {
    rollout.status = 'completed';
    rollout.completedAt = at;
    appendEvent(rollout, 'completed', opts.actor, at, {});
  } else {
    rollout.currentShard += 1;
    rollout.status = 'ready';
    appendEvent(rollout, 'next-shard-unlocked', opts.actor, at, {
      nextShardId: rollout.currentShard
    });
  }
  rollout.updatedAt = at;
  return rollout;
}

function rollback(rollout, input, options) {
  const body = input || {};
  const opts = options || {};
  if (rollout.status === 'completed' || rollout.status === 'rolled_back') {
    throw new Error('这个发布已经结束，不能重复回滚');
  }
  if (text(body.confirmation, 40) !== '停止并回滚') {
    throw new Error('请输入确认口令「停止并回滚」');
  }
  const at = opts.now || new Date().toISOString();
  rollout.status = 'rolled_back';
  rollout.rolledBackAt = at;
  rollout.rollbackReason = text(body.reason, 500) || '人工停止';
  const shard = currentShardOf(rollout);
  if (shard && shard.status !== 'pending') shard.status = 'rolled_back';
  appendEvent(rollout, 'rolled-back', opts.actor, at, {
    reason: rollout.rollbackReason
  });
  rollout.updatedAt = at;
  return rollout;
}

class ShardMaintenanceStore {
  constructor(file, options) {
    this.file = path.resolve(String(file || ''));
    this.lockFile = this.file + '.lock';
    this.now = (options && options.now) || (() => new Date().toISOString());
    this.id = (options && options.id) || (() => crypto.randomUUID());
    this.data = { version: 1, rollouts: [] };
  }

  load() {
    try {
      const parsed = JSON.parse(fs.readFileSync(this.file, 'utf8'));
      this.data = {
        version: 1,
        rollouts: Array.isArray(parsed.rollouts) ? parsed.rollouts : []
      };
    } catch (_) {
      this.data = { version: 1, rollouts: [] };
    }
    return this.data;
  }

  withLock(action) {
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    let lock = null;
    try {
      lock = fs.openSync(this.lockFile, 'wx');
    } catch (error) {
      let stale = false;
      try {
        stale = Date.now() - fs.statSync(this.lockFile).mtimeMs > 60000;
      } catch (_) {
        stale = false;
      }
      if (!stale) throw new Error('另一个维护操作正在执行，请稍后刷新');
      try { fs.unlinkSync(this.lockFile); } catch (_) { /* retry once */ }
      try {
        lock = fs.openSync(this.lockFile, 'wx');
      } catch (_) {
        throw new Error('另一个维护操作正在执行，请稍后刷新');
      }
    }
    try {
      fs.writeSync(lock, JSON.stringify({
        pid: process.pid,
        at: new Date().toISOString()
      }));
      fs.closeSync(lock);
      lock = null;
      this.load();
      const result = action();
      this.save();
      return result;
    } finally {
      if (lock !== null) {
        try { fs.closeSync(lock); } catch (_) { /* ignore */ }
      }
      try { fs.unlinkSync(this.lockFile); } catch (_) { /* ignore */ }
    }
  }

  save() {
    this.data.rollouts = this.data.rollouts.slice(0, 30);
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    const temporary = this.file + '.' + process.pid + '.tmp';
    fs.writeFileSync(temporary, JSON.stringify(this.data, null, 2));
    fs.renameSync(temporary, this.file);
  }

  list() {
    this.load();
    return clone(this.data.rollouts);
  }

  get(id) {
    this.load();
    const rollout = this.data.rollouts.find((row) => row.id === id);
    if (!rollout) throw new Error('找不到这次发布记录');
    return rollout;
  }

  create(input, actor) {
    return this.withLock(() => {
      if (this.data.rollouts.some((row) => !TERMINAL_STATES.has(row.status))) {
        throw new Error('已有未结束的发布，请先完成或回滚');
      }
      const rollout = createRollout(input, {
        now: this.now(),
        id: this.id(),
        actor
      });
      this.data.rollouts.unshift(rollout);
      return clone(rollout);
    });
  }

  transition(id, action, input, actor) {
    return this.withLock(() => {
      const rollout = this.get(id);
      const options = { now: this.now(), actor };
      if (action === 'ready') markReady(rollout, input, options);
      else if (action === 'deploy') deployCurrent(rollout, options);
      else if (action === 'claim') claimCurrent(rollout, input, options);
      else if (action === 'complete') completeCurrent(rollout, input, options);
      else if (action === 'fail') failExecution(rollout, input, options);
      else if (action === 'health') reportHealth(rollout, input, options);
      else if (action === 'approve') approveNext(rollout, input, options);
      else if (action === 'rollback') rollback(rollout, input, options);
      else throw new Error('不认识的维护操作');
      return clone(rollout);
    });
  }
}

module.exports = {
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
};
