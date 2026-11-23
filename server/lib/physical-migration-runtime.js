'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { validateFleetPlan } = require('./fleet-release-plan');
const { buildPhysicalScalePlan } = require('./physical-scale-plan');
const { executePhysicalScale } = require('./physical-scale-orchestrator');
const {
  createPhysicalScaleProductionAdapters
} = require('./physical-scale-production-adapters');
const { createSshRunner } = require('./physical-remote-runner');

function readJson(file, fallback) {
  try { return JSON.parse(fs.readFileSync(path.resolve(file), 'utf8')); }
  catch (error) {
    if (fallback !== undefined && error && error.code === 'ENOENT') return fallback;
    throw error;
  }
}

function atomicJson(file, value) {
  const target = path.resolve(file);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  const temporary = target + '.' + process.pid + '.tmp';
  fs.writeFileSync(temporary, JSON.stringify(value, null, 2) + '\n', 'utf8');
  fs.renameSync(temporary, target);
}

function appendJsonl(file, value) {
  const target = path.resolve(file);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.appendFileSync(target, JSON.stringify(value) + '\n', 'utf8');
}

function digest(value) {
  return crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
}

function nowIso(now) {
  return new Date(Number(now) || Date.now()).toISOString();
}

class PhysicalMigrationRuntime {
  constructor(options) {
    const opts = options || {};
    this.configFile = path.resolve(String(opts.configFile || ''));
    this.config = Object.assign({
      allowExplicitMigration: false,
      promoteOnSuccess: false,
      soakMinutes: 30
    }, opts.config || (this.configFile
      ? readJson(this.configFile) : {}));
    for (const key of [
      'sourcePlanFile',
      'targetPlanFile',
      'requestFile',
      'stateFile',
      'auditFile'
    ]) {
      if (!this.config[key]) throw new Error('migration config missing ' + key);
    }
    this.adapterFactoryOverride = typeof opts.adapterFactory === 'function'
      ? opts.adapterFactory : null;
    this.now = typeof opts.now === 'function' ? opts.now : () => Date.now();
  }

  plan(file) {
    const value = readJson(file);
    const validation = validateFleetPlan(value);
    if (!validation.ok) {
      const error = new Error('fleet plan validation failed');
      error.failures = validation.failures;
      throw error;
    }
    return Object.assign({}, value, validation.normalized, {
      deploymentEligible: validation.deploymentEligible,
      warnings: validation.warnings
    });
  }

  state() {
    return readJson(this.config.stateFile, {
      version: 1,
      status: 'idle',
      busy: false,
      lastResult: null
    });
  }

  adapterFactory(source, target) {
    if (this.adapterFactoryOverride) {
      return this.adapterFactoryOverride(source, target);
    }
    const cfg = this.config;
    const routePlan = readJson(cfg.routePlanFile);
    return createPhysicalScaleProductionAdapters({
      sourcePlan: source,
      targetPlan: target,
      routePlan: {
        hash: String(routePlan.hash || ''),
        fileSha256: String(cfg.routePlanFileSha256 || ''),
        bytes: fs.readFileSync(path.resolve(cfg.routePlanFile))
      },
      routePlanFile: cfg.remoteRoutePlanFile || cfg.routePlanFile,
      secretFile: cfg.secretFile,
      gateway: cfg.gateway,
      remote: cfg.remote,
      runner: createSshRunner(cfg.ssh || {}),
      provisioning: cfg.provisioning,
      soakMinutes: cfg.soakMinutes || 30,
      minimumFreeBytes: cfg.minimumFreeBytes,
      minimumFreeInodes: cfg.minimumFreeInodes
    });
  }

  async submit(input) {
    if (this.config.allowExplicitMigration !== true) {
      return { ok: false, reason: 'explicit-migration-disabled' };
    }
    const candidate = input && input.plan;
    const validation = validateFleetPlan(candidate);
    if (!validation.ok || !validation.deploymentEligible) {
      return {
        ok: false,
        reason: 'target-plan-not-production-eligible',
        failures: validation.failures,
        warnings: validation.warnings
      };
    }
    const current = this.state();
    if (current.busy === true && current.status !== 'awaiting-worker') {
      return { ok: false, reason: 'migration-already-running' };
    }
    atomicJson(this.config.targetPlanFile, candidate);
    const request = {
      version: 1,
      id: 'migration-' + crypto.randomUUID(),
      status: 'awaiting-worker',
      createdAt: nowIso(this.now()),
      actor: input.actor || {},
      sourceTopology: this.plan(this.config.sourcePlanFile).topologyId,
      targetTopology: validation.normalized.topologyId,
      targetPlanHash: digest(candidate)
    };
    atomicJson(this.config.requestFile, request);
    atomicJson(this.config.stateFile, Object.assign({}, current, {
      version: 1,
      status: 'awaiting-worker',
      busy: false,
      request,
      lastResult: null
    }));
    return { ok: true, reason: 'migration-queued', request };
  }

  async runOnce() {
    const lockFile = path.resolve(this.config.lockFile
      || this.config.stateFile + '.lock');
    fs.mkdirSync(path.dirname(lockFile), { recursive: true });
    let lock = null;
    try {
      lock = fs.openSync(lockFile, 'wx', 0o600);
    } catch (error) {
      if (error && error.code === 'EEXIST') {
        return { ok: false, reason: 'migration-job-locked' };
      }
      throw error;
    }
    try {
      return await this.runLocked();
    } finally {
      try { fs.closeSync(lock); } catch (_) { /* already closed */ }
      try { fs.unlinkSync(lockFile); } catch (_) { /* disappeared */ }
    }
  }

  async runLocked() {
    const request = readJson(this.config.requestFile, null);
    if (!request || request.version !== 1 || !request.id) {
      return { ok: true, reason: 'no-migration-request' };
    }
    if (request.status === 'completed' || request.status === 'failed') {
      return { ok: request.status === 'completed', reason: request.status,
        requestId: request.id };
    }
    if (this.config.allowExplicitMigration !== true) {
      return { ok: false, reason: 'explicit-migration-disabled' };
    }
    const source = this.plan(this.config.sourcePlanFile);
    const target = this.plan(this.config.targetPlanFile);
    if (!target.deploymentEligible) {
      return { ok: false, reason: 'target-plan-not-production-eligible',
        warnings: target.warnings };
    }
    if (digest(readJson(this.config.targetPlanFile)) !== request.targetPlanHash) {
      return { ok: false, reason: 'target-plan-changed-after-queue' };
    }
    const plan = buildPhysicalScalePlan(source, target, {
      allowScaleIn: true,
      maxShardMoves: target.shardCount,
      soakMinutes: this.config.soakMinutes || 30
    });
    if (!plan.ok) {
      const failed = {
        version: 1,
        ok: false,
        reason: 'migration-plan-invalid',
        failures: plan.failures
      };
      this.finish(request, failed);
      return failed;
    }
    atomicJson(this.config.stateFile, {
      version: 1,
      status: 'running',
      busy: true,
      request,
      startedAt: nowIso(this.now()),
      lastResult: null
    });
    let adapters;
    let result;
    try {
      adapters = await this.adapterFactory(source, target);
      result = await executePhysicalScale(plan, adapters, {
        retries: this.config.retries || 2
      });
      if (result.ok) {
        const targetIds = new Set(target.cells.map((cell) => cell.id));
        const removed = source.cells.filter((cell) => !targetIds.has(cell.id));
        if (removed.length) {
          if (typeof adapters.decommissionNode !== 'function') {
            result = {
              ok: false,
              reason: 'decommission-adapter-missing',
              events: result.events
            };
          } else {
            const decommissioned = [];
            for (const cell of removed) {
              decommissioned.push(await adapters.decommissionNode(cell));
            }
            result.decommissionedCells = decommissioned;
          }
        }
      }
      if (result.ok && this.config.promoteOnSuccess === true) {
        atomicJson(this.config.sourcePlanFile, target);
      }
    } catch (error) {
      result = {
        version: 1,
        ok: false,
        reason: 'migration-execution-error',
        error: String(error && error.message || error)
      };
    }
    return this.finish(request, result, adapters);
  }

  finish(request, result, adapters) {
    const status = result.ok ? 'completed' : 'failed';
    const receipt = Object.assign({
      version: 1,
      id: request.id,
      status,
      finishedAt: nowIso(this.now()),
      sourceTopology: request.sourceTopology,
      targetTopology: request.targetTopology
    }, result);
    atomicJson(this.config.requestFile,
      Object.assign({}, request, { status, finishedAt: receipt.finishedAt }));
    atomicJson(this.config.stateFile, {
      version: 1,
      status,
      busy: false,
      request: Object.assign({}, request, { status }),
      lastResult: receipt,
      adapterFingerprint: adapters && adapters.fingerprint || ''
    });
    appendJsonl(this.config.auditFile, receipt);
    return receipt;
  }
}

module.exports = {
  PhysicalMigrationRuntime,
  appendJsonl,
  atomicJson,
  digest
};
