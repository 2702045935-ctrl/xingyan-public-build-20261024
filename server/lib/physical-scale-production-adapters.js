'use strict';

const crypto = require('crypto');
const { validateFleetPlan } = require('./fleet-release-plan');

function text(value, label) {
  const out = String(value == null ? '' : value).trim();
  if (!out) throw new Error(label + ' is required');
  return out;
}

function host(value) {
  const out = text(value, 'host');
  if (!/^(?:\d{1,3}\.){3}\d{1,3}$/.test(out)
      && !/^[a-z0-9][a-z0-9.-]*$/i.test(out)) {
    throw new Error('invalid host: ' + out);
  }
  return out;
}

function absolute(value, label) {
  const out = text(value, label);
  if (!out.startsWith('/') || out.split('/').includes('..')) {
    throw new Error(label + ' must be an absolute safe path');
  }
  return out;
}

function digest(value) {
  return crypto.createHash('sha256')
    .update(typeof value === 'string' ? value : JSON.stringify(value))
    .digest('hex');
}

function jsonPayload(value) {
  return Buffer.from(JSON.stringify(value), 'utf8').toString('base64');
}

function shellQuote(value) {
  return "'" + String(value).replace(/'/g, "'\"'\"'") + "'";
}

function cellMap(plan) {
  return new Map((plan.cells || []).map((cell) => [cell.id, cell]));
}

function requireTargetPlan(plan) {
  const validation = validateFleetPlan(plan);
  const eligible = plan && plan.deploymentEligible === true
    || validation.deploymentEligible === true;
  if (!validation.ok || !eligible) {
    throw new Error('target fleet plan is not production eligible');
  }
}

function createPhysicalScaleProductionAdapters(options) {
  const opts = options || {};
  const source = opts.sourcePlan;
  const target = opts.targetPlan;
  requireTargetPlan(target);
  const sourceCells = cellMap(source);
  const targetCells = cellMap(target);
  const runner = opts.runner;
  if (!runner || typeof runner.run !== 'function') {
    throw new Error('remote runner is required');
  }
  const gateway = opts.gateway || {};
  const gatewayHost = host(gateway.host);
  const gatewayService = text(gateway.service, 'gateway.service');
  const gatewayHealthPort = Number(gateway.healthPort);
  if (!Number.isInteger(gatewayHealthPort) || gatewayHealthPort <= 0) {
    throw new Error('gateway.healthPort is required');
  }
  const remote = opts.remote || {};
  const user = text(remote.user || 'root', 'remote.user');
  const nodePath = absolute(remote.nodePath || '/opt/node24/bin/node',
    'remote.nodePath');
  const agentPath = absolute(remote.agentPath
    || '/opt/xingyan-dual-cell/release-r1/deploy/fleet/fleet-node-control.js',
  'remote.agentPath');
  const routePlan = opts.routePlan;
  if (!routePlan || !Buffer.isBuffer(routePlan.bytes)) {
    throw new Error('routePlan.bytes is required');
  }
  const routeFile = absolute(opts.routePlanFile || '/opt/xingyan-dual-cell/route-plan.json',
    'routePlanFile');
  const gatewayRoutingFile = absolute(gateway.routingFile
    || '/opt/xingyan-dual-cell/gateway-routing.json', 'gateway.routingFile');
  const secretFile = absolute(opts.secretFile
    || '/opt/xingyan-dual-cell/key-domain/secret.key', 'secretFile');
  const remoteFleetPlanFile = absolute(opts.remoteFleetPlanFile
    || '/etc/xingyan-dual-cell/current-fleet.json', 'remoteFleetPlanFile');
  const provisioning = Object.assign({
    enabled: false,
    sourceUser: 'root',
    sourceRoot: '/opt/xingyan-dual-cell/release-r1',
    clusterKeyFile: '/root/.ssh/xingyan-cluster',
    envDir: '/etc/xingyan-dual-cell',
    unitDir: '/etc/systemd/system'
  }, opts.provisioning || {});
  const provisioningReleaseRoot = absolute(
    provisioning.releaseRoot || '/opt/xingyan-dual-cell/release-r1',
    'provisioning.releaseRoot'
  );
  const provisioningSourceRoot = absolute(
    provisioning.sourceRoot || '/opt/xingyan-dual-cell/release-r1',
    'provisioning.sourceRoot'
  );
  const provisioningKeyFile = absolute(
    provisioning.clusterKeyFile || '/root/.ssh/xingyan-cluster',
    'provisioning.clusterKeyFile'
  );
  const timeoutMs = Math.max(5000, Number(opts.timeoutMs) || 300000);
  const routeSha = crypto.createHash('sha256').update(routePlan.bytes).digest('hex');
  if (routePlan.fileSha256 && routeSha !== routePlan.fileSha256) {
    throw new Error('route plan file hash mismatch');
  }

  const call = (targetHost, action, payload) => runner.run({
    host: host(targetHost),
    user: user,
    argv: [nodePath, agentPath, action, jsonPayload(payload)],
    timeoutMs: timeoutMs,
    purpose: action
  });

  const bootstrapProvisioning = async (cell, seedCell) => {
    const launcher = provisioningReleaseRoot + '/run-dual-cell-shard.sh';
    const command = [
      'set -euo pipefail',
      'mkdir -p ' + shellQuote(provisioningReleaseRoot)
        + ' ' + shellQuote(cell.dataRoot),
      'test -f ' + shellQuote(provisioningKeyFile),
      'if [ ! -f ' + shellQuote(launcher) + ' ]; then',
      '  rsync -aH --checksum --delete-delay --exclude=*.tmp --exclude=*.part'
        + ' -e ' + shellQuote('ssh -i ' + provisioningKeyFile
          + ' -o BatchMode=yes -o StrictHostKeyChecking=accept-new')
        + ' ' + shellQuote(provisioning.sourceUser + '@'
          + seedCell.host + ':' + provisioningSourceRoot + '/')
        + ' ' + shellQuote(provisioningReleaseRoot + '/'),
      'fi',
      'test -f ' + shellQuote(launcher),
      'test -f ' + shellQuote(provisioningReleaseRoot
        + '/deploy/fleet/fleet-node-control.js')
    ].join('\n');
    const result = await runner.run({
      host: host(cell.host),
      user,
      argv: ['/bin/bash', '-lc', shellQuote(command)],
      timeoutMs: Math.max(timeoutMs, 30 * 60 * 1000),
      purpose: 'bootstrap-provision'
    });
    return result || { ok: true };
  };

  const targetCell = (id) => {
    const cell = targetCells.get(id);
    if (!cell) throw new Error('target cell not found: ' + id);
    return cell;
  };
  const sourceCell = (id) => {
    const cell = sourceCells.get(id);
    if (!cell) throw new Error('source cell not found: ' + id);
    return cell;
  };
  const portFor = (cell, shard) => Number(cell.ports[shard]);

  return {
    async prepareNode(row) {
      const cell = targetCell(row.cellId);
      if (provisioning.enabled === true) {
        const seedCell = sourceCell(provisioning.seedCellId
          || (source.cells[0] && source.cells[0].id));
        const servicePrefix = text(cell.servicePrefix, 'servicePrefix');
        const envFile = absolute(provisioning.envDir + '/' + servicePrefix + '.env',
          'provision envFile');
        const unitFile = absolute(provisioning.unitDir + '/'
          + servicePrefix + '@.service', 'provision unitFile');
        const sourcePlanBytes = Buffer.from(JSON.stringify(source, null, 2) + '\n');
        const fleetPlanSha256 = crypto.createHash('sha256')
          .update(sourcePlanBytes).digest('hex');
        await bootstrapProvisioning(cell, seedCell);
        const result = await call(cell.host, 'provision', {
          cellId: cell.id,
          sourceHost: seedCell.host,
          sourceUser: provisioning.sourceUser,
          sourceRoot: provisioningSourceRoot,
          releaseRoot: provisioningReleaseRoot,
          dataRoot: absolute(cell.dataRoot, 'dataRoot'),
          servicePrefix,
          envFile,
          unitFile,
          shardCount: target.shardCount,
          ports: cell.ports,
          ownerPorts: Array.from({ length: target.shardCount }, (_, shard) => {
            const owner = target.cells.find((candidate) =>
              candidate.ownerShards.includes(shard));
            return portFor(owner, shard);
          }),
          routePlan: routeFile,
          routePlanSha256: routeSha,
          routeSourceFile: provisioning.routeSourceFile || routeFile,
          secretFile,
          secretSourceFile: provisioning.secretSourceFile || secretFile,
          fleetPlan: remoteFleetPlanFile,
          fleetPlanContentBase64: sourcePlanBytes.toString('base64'),
          fleetPlanSha256,
          nodeBin: nodePath,
          busAddr: provisioning.busAddr || '127.0.0.1:16400',
          clusterKeyFile: provisioning.clusterKeyFile,
          minimumFreeBytes: Number(opts.minimumFreeBytes) || 10 * 1024 * 1024 * 1024,
          minimumFreeInodes: Number(opts.minimumFreeInodes) || 100000
        });
        if (!result || result.ok !== true) throw new Error('provision-node failed');
        return result;
      }
      const result = await call(cell.host, 'prepare', {
        dataRoot: absolute(cell.dataRoot, 'dataRoot'),
        shardCount: target.shardCount,
        servicePrefix: cell.servicePrefix,
        ports: cell.ports,
        minimumFreeBytes: Number(opts.minimumFreeBytes) || 10 * 1024 * 1024 * 1024,
        minimumFreeInodes: Number(opts.minimumFreeInodes) || 100000
      });
      if (!result || result.ok !== true) throw new Error('prepare-node failed');
      return result;
    },

    async seedReplica(move) {
      const from = sourceCell(move.fromCellId);
      const to = targetCell(move.toCellId);
      const result = await call(to.host, 'replicate', {
        sourceHost: host(from.host),
        sourceUser: user,
        sourceRoot: absolute(from.dataRoot + '/' + move.shard, 'sourceRoot'),
        targetRoot: absolute(to.dataRoot + '/' + move.shard, 'targetRoot')
      });
      if (!result || result.ok !== true) throw new Error('replica seed failed');
      return result;
    },

    async waitReplicaCaughtUp(move) {
      const from = sourceCell(move.fromCellId);
      const to = targetCell(move.toCellId);
      const [sourceManifest, targetManifest] = await Promise.all([
        call(from.host, 'manifest', {
          root: absolute(from.dataRoot + '/' + move.shard, 'sourceRoot')
        }),
        call(to.host, 'manifest', {
          root: absolute(to.dataRoot + '/' + move.shard, 'targetRoot')
        })
      ]);
      if (!sourceManifest || !targetManifest || !sourceManifest.hash
          || sourceManifest.hash !== targetManifest.hash) {
        throw new Error('replica manifest mismatch for shard ' + move.shard);
      }
      return { hash: sourceManifest.hash, files: sourceManifest.files };
    },

    async shadowRead(move) {
      const to = targetCell(move.toCellId);
      const result = await call(to.host, 'health-one', {
        port: portFor(to, move.shard),
        expectedPlanHash: routePlan.hash,
        expectedFileSha256: routeSha
      });
      if (!result || result.ok !== true) throw new Error('shadow read failed');
      return result;
    },

    async freezeOwner(move) {
      const from = sourceCell(move.fromCellId);
      const result = await call(from.host, 'freeze-one', {
        port: portFor(from, move.shard),
        planFile: routeFile,
        secretFile: secretFile,
        reason: 'physical-scale-' + move.shard
      });
      if (!result || result.ok !== true || result.frozen !== true) {
        throw new Error('freeze owner failed');
      }
      return result;
    },

    async acquireLease(move) {
      const to = targetCell(move.toCellId);
      const result = await call(to.host, 'owner-one', {
        port: portFor(to, move.shard),
        planFile: routeFile,
        secretFile: secretFile,
        enable: move.rollback !== true
      });
      if (!result || result.ok !== true) throw new Error('lease acquisition failed');
      return result;
    },

    async switchRoutes(move) {
      const ownerPorts = Array.from({ length: target.shardCount }, (_, shard) => {
        const owner = target.cells.find((cell) => cell.ownerShards.includes(shard));
        if (!owner) throw new Error('target owner missing for shard ' + shard);
        return portFor(owner, shard);
      });
      const ownerTargets = Array.from({ length: target.shardCount }, (_, shard) => {
        const owner = target.cells.find((cell) => cell.ownerShards.includes(shard));
        return 'http://' + owner.host + ':' + portFor(owner, shard);
      });
      const result = await call(gatewayHost, 'write-gateway-routing', {
        path: gatewayRoutingFile,
        ownerPorts: ownerPorts,
        ownerTargets: ownerTargets,
        routePlanHash: routePlan.hash,
        rollback: move.rollback === true
      });
      if (!result || result.ok !== true) {
        throw new Error('gateway routing staging failed');
      }
      return result;
    },

    async switchGateway(move) {
      const result = await call(gatewayHost, 'reload-gateway', {
        service: gatewayService,
        port: gatewayHealthPort,
        expectedPlanHash: routePlan.hash,
        expectedFileSha256: routeSha,
        rollback: move.rollback === true
      });
      if (!result || result.ok !== true || result.reloadMode !== 'SIGHUP') {
        throw new Error('gateway hot reload failed');
      }
      return result;
    },

    async unfreezeOwner(move) {
      const to = targetCell(move.toCellId);
      const result = await call(to.host, 'unfreeze-one', {
        port: portFor(to, move.shard),
        planFile: routeFile,
        secretFile: secretFile
      });
      if (!result || result.ok !== true || result.frozen !== false) {
        throw new Error('unfreeze target owner failed');
      }
      return result;
    },

    async verifyOwner(move) {
      const to = targetCell(move.toCellId);
      const result = await call(to.host, 'verify-one', {
        port: portFor(to, move.shard),
        expectedPlanHash: routePlan.hash,
        expectedFileSha256: routeSha,
        expectedOwnerCell: move.rollback === true ? move.fromCellId : move.toCellId
      });
      if (!result || result.ok !== true) throw new Error('owner verification failed');
      return result;
    },

    async switchReplication(move) {
      const plan = move.rollback === true ? source : target;
      const bytes = Buffer.from(JSON.stringify(plan, null, 2) + '\n');
      const sha256 = crypto.createHash('sha256').update(bytes).digest('hex');
      const hosts = Array.from(new Set([
        ...source.cells.map((cell) => cell.host),
        ...target.cells.map((cell) => cell.host),
        gatewayHost
      ]));
      const rows = await Promise.all(hosts.map((targetHost) =>
        call(targetHost, 'write-fleet-plan', {
          path: remoteFleetPlanFile,
          contentBase64: bytes.toString('base64'),
          sha256
        })
      ));
      if (rows.some((row) => !row || row.ok !== true || row.sha256 !== sha256)) {
        throw new Error('replication topology handoff failed');
      }
      return { ok: true, topologyId: plan.topologyId, sha256, hosts };
    },

    async decommissionNode(cell) {
      const removed = sourceCells.get(cell.id) || cell;
      if (!removed || !removed.host) {
        throw new Error('decommission cell is invalid');
      }
      const result = await call(removed.host, 'decommission', {
        cellId: removed.id,
        servicePrefix: removed.servicePrefix,
        dataRoot: absolute(removed.dataRoot, 'dataRoot'),
        shardCount: target.shardCount,
        fleetPlan: remoteFleetPlanFile
      });
      if (!result || result.ok !== true || result.dataPreserved !== true) {
        throw new Error('decommission-node failed');
      }
      return result;
    },

    async soak(plan) {
      const durationMinutes = Math.max(1, Number(opts.soakMinutes) || 1);
      const durationMs = Number.isFinite(Number(opts.soakDurationMs))
        ? Math.max(1, Number(opts.soakDurationMs))
        : durationMinutes * 60 * 1000;
      const end = Date.now() + durationMs;
      let samples = 0;
      do {
        const result = await call(gatewayHost, 'health-one', {
          port: gatewayHealthPort,
          expectedPlanHash: routePlan.hash,
          expectedFileSha256: routeSha
        });
        if (!result || result.ok !== true) throw new Error('gateway soak failed');
        samples += 1;
        if (Date.now() < end) {
          await new Promise((resolve) => setTimeout(resolve,
            Math.min(30000, Math.max(1, durationMs))));
        }
      } while (Date.now() < end);
      return { ok: true, samples, durationMinutes, planFingerprint: plan.fingerprint };
    },

    fingerprint: digest({
      sourceTopology: source.topologyId,
      targetTopology: target.topologyId,
      routeSha,
      gatewayHost,
      gatewayService,
      agentPath
    })
  };
}

module.exports = {
  createPhysicalScaleProductionAdapters
};
