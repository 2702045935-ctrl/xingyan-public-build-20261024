'use strict';

const fs = require('fs');
const path = require('path');
const { validateFleetPlan } = require('./fleet-release-plan');
const { loadFleetControlPanel } = require('./fleet-control-panel');

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

    if (parts[1] === 'fleet' && parts.length === 2 && method === 'GET') {
      let plan = null;
      try { plan = JSON.parse(fs.readFileSync(fleetPath, 'utf8')); }
      catch (_) { plan = fallbackPlan(); }
      if (!plan) {
        fail(res, 404, '没有 Fleet 计划文件');
        return true;
      }
      ok(res, {
        path: fleetPath,
        targetPath,
        plan,
        currentPlan: plan,
        candidatePlan: (() => {
          try { return JSON.parse(fs.readFileSync(targetPath, 'utf8')); }
          catch (_) { return null; }
        })(),
        validation: validateFleetPlan(plan)
      });
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
            || '/var/lib/xingyan-dual-cell/failover-audit.jsonl'
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
