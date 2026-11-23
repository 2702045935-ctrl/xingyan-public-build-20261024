'use strict';

const crypto = require('crypto');

function text(value, label) {
  const out = String(value == null ? '' : value).trim();
  if (!out) throw new Error(label + ' is required');
  return out;
}

function safeAbsolute(value, label) {
  const out = text(value, label);
  if (!out.startsWith('/') || out.split('/').includes('..')) {
    throw new Error(label + ' must be an absolute safe path');
  }
  return out;
}

function safeName(value, label) {
  const out = text(value, label);
  if (!/^[a-z0-9][a-z0-9_.@-]*$/i.test(out)) {
    throw new Error(label + ' contains unsafe characters');
  }
  return out;
}

function positivePorts(value, shardCount) {
  const ports = (Array.isArray(value) ? value : []).map(Number);
  if (ports.length !== shardCount
      || ports.some((port) => !Number.isInteger(port) || port <= 0)) {
    throw new Error('ports must contain one positive port per shard');
  }
  if (new Set(ports).size !== ports.length) {
    throw new Error('ports must be unique');
  }
  return ports;
}

function integerList(value, shardCount) {
  const rows = Array.from(new Set((Array.isArray(value) ? value : []).map(Number)));
  if (rows.some((shard) => !Number.isInteger(shard)
      || shard < 0 || shard >= shardCount)) {
    throw new Error('ownedShards contains an invalid shard');
  }
  return rows.sort((left, right) => left - right);
}

function envContent(input) {
  const shardCount = Number(input.shardCount);
  if (!Number.isInteger(shardCount) || shardCount < 1 || shardCount > 128) {
    throw new Error('shardCount is invalid');
  }
  const cellId = safeName(input.cellId, 'cellId');
  const servicePrefix = safeName(input.servicePrefix, 'servicePrefix');
  const dataRoot = safeAbsolute(input.dataRoot, 'dataRoot');
  const releaseRoot = safeAbsolute(input.releaseRoot, 'releaseRoot');
  const routePlan = safeAbsolute(input.routePlan, 'routePlan');
  const routeSha = text(input.routePlanSha256, 'routePlanSha256').toLowerCase();
  if (!/^[a-f0-9]{64}$/.test(routeSha)) {
    throw new Error('routePlanSha256 is invalid');
  }
  const ports = positivePorts(input.ports, shardCount);
  const ownerPorts = positivePorts(input.ownerPorts, shardCount);
  const ownedShards = integerList(input.ownedShards || [], shardCount);
  const fleetPlan = safeAbsolute(input.fleetPlan, 'fleetPlan');
  const nodeBin = safeAbsolute(input.nodeBin || '/opt/node24/bin/node', 'nodeBin');
  const busAddr = text(input.busAddr || '127.0.0.1:16400', 'busAddr');
  if (!/^(?:[a-z0-9.-]+|\[[a-f0-9:]+\]):\d{1,5}$/i.test(busAddr)) {
    throw new Error('busAddr is invalid');
  }
  const values = [
    ['DUAL_CELL_ID', cellId],
    ['DUAL_CELL_SHARD_COUNT', shardCount],
    ['DUAL_CELL_DATA_ROOT', dataRoot],
    ['DUAL_CELL_DATA_LAYOUT', 'shards'],
    ['DUAL_CELL_RUNTIME_BASE_PORT', ports[0]],
    ['DUAL_CELL_SHARD_PORTS', ports.join(',')],
    ['DUAL_CELL_ROUTE_PLAN', routePlan],
    ['DUAL_CELL_ROUTE_PLAN_SHA256', routeSha],
    ['DUAL_CELL_OWNER_PORTS', ownerPorts.join(',')],
    ['DUAL_CELL_OWNED_SHARDS', ownedShards.join(',')],
    ['DUAL_CELL_FLEET_PLAN', fleetPlan],
    ['DUAL_CELL_SERVICE_PREFIX', servicePrefix],
    ['DUAL_CELL_RELEASE_ROOT', releaseRoot],
    ['DUAL_CELL_NODE_BIN', nodeBin],
    ['DUAL_CELL_BUS_ADDR', busAddr],
    ['SHARD_AUTHORITY_ENABLED', '1'],
    ['SHARD_AUTHORITY_REQUIRED', '1'],
    ['SHARD_AUTHORITY_SHARDS', ownedShards.join(',')],
    ['SHARD_AUTHORITY_READ', '1'],
    ['SHARD_AUTHORITY_WRITE', '1']
  ];
  for (const [key, value] of values) {
    if (/\r|\n/.test(String(value))) {
      throw new Error(key + ' contains a newline');
    }
  }
  return values.map(([key, value]) => key + '=' + value).join('\n') + '\n';
}

function serviceUnit(input) {
  const servicePrefix = safeName(input.servicePrefix, 'servicePrefix');
  const envFile = safeAbsolute(input.envFile, 'envFile');
  const releaseRoot = safeAbsolute(input.releaseRoot, 'releaseRoot');
  const description = safeName(input.cellId, 'cellId');
  return [
    '[Unit]',
    'Description=Xingyan fleet cell ' + description + ' shard %i',
    'After=network-online.target',
    'Wants=network-online.target',
    '',
    '[Service]',
    'Type=simple',
    'EnvironmentFile=' + envFile,
    'ExecStart=' + releaseRoot + '/run-dual-cell-shard.sh %i',
    'Restart=always',
    'RestartSec=3',
    'LimitNOFILE=65535',
    'NoNewPrivileges=true',
    'PrivateTmp=true',
    '',
    '[Install]',
    'WantedBy=multi-user.target',
    ''
  ].join('\n');
}

function buildNodeProvisionPlan(input) {
  const sourceHost = safeName(input.sourceHost, 'sourceHost');
  const sourceRoot = safeAbsolute(input.sourceRoot, 'sourceRoot');
  const releaseRoot = safeAbsolute(input.releaseRoot, 'releaseRoot');
  const dataRoot = safeAbsolute(input.dataRoot, 'dataRoot');
  const servicePrefix = safeName(input.servicePrefix, 'servicePrefix');
  const cellId = safeName(input.cellId, 'cellId');
  const envFile = safeAbsolute(input.envFile, 'envFile');
  const unitFile = safeAbsolute(input.unitFile, 'unitFile');
  const fleetPlan = safeAbsolute(input.fleetPlan, 'fleetPlan');
  const routePlan = safeAbsolute(input.routePlan, 'routePlan');
  const routeSourceFile = safeAbsolute(input.routeSourceFile, 'routeSourceFile');
  const secretFile = safeAbsolute(input.secretFile, 'secretFile');
  const secretSourceFile = safeAbsolute(input.secretSourceFile, 'secretSourceFile');
  const shardCount = Number(input.shardCount);
  const env = envContent(Object.assign({}, input, {
    sourceHost,
    sourceRoot,
    releaseRoot,
    dataRoot,
    servicePrefix,
    cellId,
    envFile,
    unitFile,
    fleetPlan,
    routePlan,
    routeSourceFile,
    secretFile,
    secretSourceFile,
    shardCount
  }));
  const unit = serviceUnit(Object.assign({}, input, {
    servicePrefix,
    envFile,
    releaseRoot,
    cellId
  }));
  const fingerprint = crypto.createHash('sha256').update(JSON.stringify({
    sourceHost,
    sourceRoot,
    releaseRoot,
    dataRoot,
    servicePrefix,
    cellId,
    envFile,
    unitFile,
    fleetPlan,
    routePlan,
    routeSourceFile,
    secretFile,
    secretSourceFile,
    shardCount,
    ports: input.ports,
    ownerPorts: input.ownerPorts
  })).digest('hex');
  return {
    version: 1,
    cellId,
    servicePrefix,
    sourceHost,
    sourceRoot,
    releaseRoot,
    dataRoot,
    envFile,
    unitFile,
    fleetPlan,
    routePlan,
    routeSourceFile,
    secretFile,
    secretSourceFile,
    shardCount,
    env,
    unit,
    fingerprint
  };
}

module.exports = {
  buildNodeProvisionPlan,
  envContent,
  serviceUnit
};
