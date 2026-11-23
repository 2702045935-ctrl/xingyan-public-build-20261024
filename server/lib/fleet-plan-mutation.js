'use strict';

const { validateFleetPlan } = require('./fleet-release-plan');

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function text(value, label) {
  const out = String(value == null ? '' : value).trim();
  if (!out) throw new Error(label + ' is required');
  return out;
}

function safePath(value, label) {
  const out = text(value, label);
  if (!out.startsWith('/') || out.split('/').includes('..')) {
    throw new Error(label + ' must be an absolute safe path');
  }
  return out;
}

function normalizeNode(input, shardCount) {
  const node = input && typeof input === 'object' ? input : {};
  const ports = (Array.isArray(node.ports) ? node.ports : []).map(Number);
  if (ports.length !== shardCount
      || ports.some((port) => !Number.isInteger(port) || port <= 0)) {
    throw new Error('node ports must contain one positive port per shard');
  }
  if (new Set(ports).size !== ports.length) {
    throw new Error('node ports must be unique');
  }
  return {
    id: text(node.id, 'node.id'),
    host: text(node.host, 'node.host'),
    failureDomain: text(node.failureDomain, 'node.failureDomain'),
    servicePrefix: text(node.servicePrefix, 'node.servicePrefix'),
    dataRoot: safePath(node.dataRoot, 'node.dataRoot'),
    replicaShards: Array.from({ length: shardCount }, (_, shard) => shard),
    ownerShards: [],
    ports
  };
}

function rebalanceCells(input) {
  const plan = clone(input);
  const cells = Array.isArray(plan.cells) ? plan.cells : [];
  if (!cells.length) throw new Error('at least one cell is required');
  for (const cell of cells) {
    cell.replicaShards = Array.from(
      { length: plan.shardCount },
      (_, shard) => shard
    );
    cell.ownerShards = [];
  }
  for (let shard = 0; shard < plan.shardCount; shard += 1) {
    const index = shard % cells.length;
    cells[index].ownerShards.push(shard);
  }
  const result = validateFleetPlan(plan);
  if (!result.ok) {
    const error = new Error('rebalanced fleet plan is invalid');
    error.failures = result.failures;
    throw error;
  }
  return Object.assign(plan, {
    deploymentEligible: result.deploymentEligible,
    warnings: result.warnings
  });
}

function rebalanceOwners(input) {
  const validation = validateFleetPlan(input);
  if (!validation.ok) {
    const error = new Error('fleet plan validation failed');
    error.failures = validation.failures;
    throw error;
  }
  return rebalanceCells(input);
}

function addNode(inputPlan, nodeInput) {
  const validation = validateFleetPlan(inputPlan);
  if (!validation.ok) throw new Error('source fleet plan is invalid');
  const plan = clone(inputPlan);
  const node = normalizeNode(nodeInput, plan.shardCount);
  if (plan.cells.some((cell) => cell.id === node.id)) {
    throw new Error('cell id already exists');
  }
  if (plan.cells.some((cell) => cell.host === node.host)) {
    throw new Error('cell host already exists');
  }
  plan.cells.push(node);
  plan.topologyId = String(plan.topologyId).replace(/-expanded-\d+$/, '')
    + '-expanded-' + plan.cells.length;
  return rebalanceCells(plan);
}

function deleteNode(inputPlan, cellId) {
  const validation = validateFleetPlan(inputPlan);
  if (!validation.ok) throw new Error('source fleet plan is invalid');
  const plan = clone(inputPlan);
  const id = text(cellId, 'cellId');
  if (!plan.cells.some((cell) => cell.id === id)) {
    throw new Error('cell does not exist');
  }
  if (plan.cells.length <= 1) throw new Error('cannot delete the last cell');
  plan.cells = plan.cells.filter((cell) => cell.id !== id);
  plan.topologyId = String(plan.topologyId).replace(/-expanded-\d+$/, '')
    + '-expanded-' + plan.cells.length;
  return rebalanceCells(plan);
}

module.exports = {
  addNode,
  deleteNode,
  normalizeNode,
  rebalanceOwners
};
