'use strict';

const fs = require('fs');
const path = require('path');
const { validateFleetPlan } = require('./fleet-release-plan');
const { loadFleetControlPanel } = require('./fleet-control-panel');
const { addNode, deleteNode, rebalanceOwners } = require('./fleet-plan-mutation');
const { PhysicalMigrationRuntime } = require('./physical-migration-runtime');

function createFleetControlHttp(deps) {
  const {
    ok,
    fail,
    readBody,
    audit,
    writeJson,
    currentOps,
    opsConfirmOk,
    root
  } = deps;

  return async function handleFleetControl(req, res, parts, method) {
    if (parts[0] !== 'ops'
        || (parts[1] !== 'fleet' && parts[1] !== 'shardmaintenance')) {
      return false;
    }
    const admin = currentOps(req);
    if (!admin) {
      fail(res, 401, '请先登录');
      return true;
    }
    if (admin.role !== 'super') {
      fail(res, 403, '控制面只有超级管理员能操作');
      return true;
    }
    const fleetPath = path.resolve(process.env.PHYSICAL_FLEET_PLAN
      || '/var/lib/xingyan-dual-cell/current-fleet.json');
    const targetPath = path.resolve(process.env.PHYSICAL_FLEET_TARGET
      || '/var/lib/xingyan-dual-cell/fleet-target.json');
    const fallbackPlan = () => {
      const candidates = [
        path.join(root, 'deploy', 'fleet', 'fleet-production.json'),
        path.join(path.dirname(root), 'deploy', 'fleet', 'fleet-production.json')
      ];
      for (const file of candidates) {
        try {
          return JSON.parse(fs.readFileSync(file, 'utf8'));
        } catch (_) { /* continue */ }
      }
      return null;
    };
    const currentPlan = () => {
      try { return JSON.parse(fs.readFileSync(fleetPath, 'utf8')); }
      catch (_) { return fallbackPlan(); }
    };
    const candidatePlan = () => {
      try { return JSON.parse(fs.readFileSync(targetPath, 'utf8')); }
      catch (_) { return null; }
    };
    const saveCandidate = (plan, adminUser, reason) => {
      const validation = validateFleetPlan(plan);
      if (!validation.ok) {
        fail(res, 422, 'Fleet 候选计划校验失败', validation.failures);
        return false;
      }
      writeJson(targetPath, plan);
      audit(req, adminUser, reason,
        validation.normalized.topologyId,
        validation.normalized.cells.length + ' Cell / '
          + validation.normalized.shardCount + ' 分片');
      return true;
    };
    const migrationRuntime = (configFile) => {
      let config = {};
      try { config = JSON.parse(fs.readFileSync(configFile, 'utf8')); }
      catch (_) { /* use environment paths */ }
      return new PhysicalMigrationRuntime({
        config: Object.assign({}, config, {
          sourcePlanFile: fleetPath,
          targetPlanFile: targetPath,
          requestFile: process.env.PHYSICAL_MIGRATION_REQUEST
            || '/var/lib/xingyan-dual-cell/migration-request.json',
          stateFile: process.env.PHYSICAL_MIGRATION_STATE
            || '/var/lib/xingyan-dual-cell/migration-state.json',
          auditFile: process.env.PHYSICAL_MIGRATION_AUDIT
            || '/var/lib/xingyan-dual-cell/migration-audit.jsonl'
        })
      });
    };

    if (parts[1] === 'fleet' && parts.length === 2 && method === 'GET') {
      let plan = null;
      try { plan = JSON.parse(fs.readFileSync(fleetPath, 'utf8')); }
      catch (_) { plan = fallbackPlan(); }
      if (!plan) {
        fail(res, 404, '没有 Fleet 计划文件');
        return true;
      }
      const candidate = candidatePlan();
      ok(res, {
        path: fleetPath,
        targetPath,
        plan,
        currentPlan: plan,
        candidatePlan: candidate,
        validation: validateFleetPlan(plan),
        candidateValidation: candidate ? validateFleetPlan(candidate) : null
      });
      return true;
    }
    if (parts[1] === 'fleet' && parts[2] === 'nodes'
        && method === 'POST' && ['add', 'delete', 'rebalance'].includes(parts[3])) {
      const body = await readBody(req);
      if (!opsConfirmOk(admin, body)) {
        fail(res, 428, '修改节点计划需要再次输入管理员密码');
        return true;
      }
      const base = candidatePlan() || currentPlan();
      if (!base) {
        fail(res, 404, '没有可编辑的 Fleet 计划');
        return true;
      }
      let next;
      try {
        if (parts[3] === 'add') next = addNode(base, body.node);
        else if (parts[3] === 'delete') next = deleteNode(base, body.cellId);
        else next = rebalanceOwners(base);
      } catch (error) {
        fail(res, 422, String(error && error.message || error));
        return true;
      }
      if (!saveCandidate(next, admin,
        parts[3] === 'add' ? '新增候选 Cell'
          : parts[3] === 'delete' ? '移除候选 Cell'
            : '重新均衡候选 Cell 分片')) return true;
      ok(res, {
        path: targetPath,
        plan: next,
        validation: validateFleetPlan(next)
      });
      return true;
    }
    if (parts[1] === 'fleet' && parts[2] === 'migration'
        && parts.length === 3 && method === 'GET') {
      const configFile = process.env.PHYSICAL_AUTO_SCALE_CONFIG
        || '/etc/xingyan-dual-cell/auto-scale.json';
      ok(res, {
        state: migrationRuntime(configFile).state(),
        request: (() => {
          try {
            return JSON.parse(fs.readFileSync(
              process.env.PHYSICAL_MIGRATION_REQUEST
                || '/var/lib/xingyan-dual-cell/migration-request.json',
              'utf8'
            ));
          } catch (_) {
            return null;
          }
        })()
      });
      return true;
    }
    if (parts[1] === 'fleet' && parts[2] === 'migration'
        && parts.length === 3 && method === 'POST') {
      const body = await readBody(req);
      if (!opsConfirmOk(admin, body)) {
        fail(res, 428, '提交生产迁移需要再次输入管理员密码');
        return true;
      }
      const configFile = process.env.PHYSICAL_AUTO_SCALE_CONFIG
        || '/etc/xingyan-dual-cell/auto-scale.json';
      const result = await migrationRuntime(configFile).submit({
        plan: body.plan || candidatePlan(),
        actor: {
          id: admin.id,
          username: admin.username,
          name: admin.name
        }
      });
      if (!result.ok) {
        fail(res, 409, result.reason, result);
        return true;
      }
      audit(req, admin, '提交物理迁移任务',
        result.request.targetTopology, result.request.id);
      ok(res, result);
      return true;
    }
    if (parts[1] === 'fleet' && parts.length === 2 && method === 'PUT') {
      const body = await readBody(req);
      if (!opsConfirmOk(admin, body)) {
        fail(res, 428, '保存生产节点计划需要再次输入管理员密码');
        return true;
      }
      const plan = body && body.plan;
      const validation = validateFleetPlan(plan);
      if (!validation.ok) {
        fail(res, 422, 'Fleet 计划校验失败', validation.failures);
        return true;
      }
      writeJson(targetPath, plan);
      audit(req, admin, '保存目标 Cell 节点计划',
        validation.normalized.topologyId,
        validation.normalized.cells.length + ' Cell / '
          + validation.normalized.shardCount + ' 分片');
      ok(res, { path: targetPath, plan, validation });
      return true;
    }
    if (parts[1] === 'shardmaintenance'
        && parts.length === 2 && method === 'GET') {
      ok(res, {
        frozen: {},
        checklist: [],
        rollouts: [],
        fleetControl: loadFleetControlPanel({
          configFile: process.env.PHYSICAL_AUTO_SCALE_CONFIG
            || '/etc/xingyan-dual-cell/auto-scale.json',
          stateFile: process.env.PHYSICAL_AUTO_SCALE_STATE
            || '/var/lib/xingyan-dual-cell/auto-scale-state.json',
          metricsFile: process.env.PHYSICAL_FLEET_METRICS
            || '/var/lib/xingyan-dual-cell/fleet-metrics.json',
          auditFile: process.env.PHYSICAL_AUTO_SCALE_AUDIT
            || '/var/lib/xingyan-dual-cell/auto-scale-audit.jsonl',
          failoverConfigFile: process.env.PHYSICAL_FAILOVER_CONFIG
            || '/etc/xingyan-dual-cell/failover.json',
          failoverStateFile: process.env.PHYSICAL_FAILOVER_STATE
            || '/var/lib/xingyan-dual-cell/failover-state.json',
          failoverAuditFile: process.env.PHYSICAL_FAILOVER_AUDIT
            || '/var/lib/xingyan-dual-cell/failover-audit.jsonl',
          migrationStateFile: process.env.PHYSICAL_MIGRATION_STATE
            || '/var/lib/xingyan-dual-cell/migration-state.json',
          migrationRequestFile: process.env.PHYSICAL_MIGRATION_REQUEST
            || '/var/lib/xingyan-dual-cell/migration-request.json'
        })
      });
      return true;
    }
    if (parts[1] === 'shardmaintenance') {
      fail(res, 503, '逐片维护执行器尚未在这台节点启用');
      return true;
    }
    fail(res, 405, 'Method Not Allowed');
    return true;
  };
}

module.exports = { createFleetControlHttp };
