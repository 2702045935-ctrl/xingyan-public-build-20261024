'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { validateActiveDualCellPlan } = require('../lib/dual-cell-active-plan');
const {
  DualCellNode,
  replicateShard,
  replicateOwnedShards,
  replicationLag
} = require('../lib/dual-cell-replication');
const {
  makeRoutePlan,
  pickUserByShard,
  makePlan
} = require('../lib/dual-cell-failover-drill');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-dual-replication-'));
try {
  const routePlan = makeRoutePlan();
  const users = pickUserByShard(routePlan);
  const plan = makePlan(routePlan, root);
  const planResult = validateActiveDualCellPlan(plan);
  assert.strictEqual(planResult.ok, true, JSON.stringify(planResult.failures));
  const coordinationDir = path.join(root, 'coordination');
  const nodeA = new DualCellNode({
    validatedPlan: planResult,
    routePlan,
    cell: 'a',
    dataRoot: path.join(root, 'cell-a'),
    coordinationDir
  });
  const nodeB = new DualCellNode({
    validatedPlan: planResult,
    routePlan,
    cell: 'b',
    dataRoot: path.join(root, 'cell-b'),
    coordinationDir
  });
  nodeA.activateBaseline();
  nodeB.activateBaseline();

  const first = nodeA.submit({
    entityType: 'user',
    entityId: users[0],
    operation: 'update',
    payload: { nickname: 'cell-a' },
    eventId: 'replication-event-1'
  });
  assert.strictEqual(first.status, 'applied');
  assert.strictEqual(first.ownerShard, 0);
  let replicated = replicateShard(nodeA, nodeB, 0);
  assert.strictEqual(replicated.applied, 1);
  assert.strictEqual(replicated.duplicate, 0);
  assert.strictEqual(nodeB.read('user', users[0]).state.payload.nickname, 'cell-a');
  assert.strictEqual(replicationLag(nodeA, nodeB).maxLag, 0);

  replicated = replicateShard(nodeA, nodeB, 0);
  assert.strictEqual(replicated.applied, 0);
  assert.strictEqual(replicated.duplicate, 0);
  const duplicate = nodeA.submit({
    entityType: 'user',
    entityId: users[0],
    operation: 'update',
    payload: { nickname: 'cell-a' },
    eventId: 'replication-event-1'
  });
  assert.strictEqual(duplicate.status, 'duplicate');

  const fenced = nodeB.submit({
    entityType: 'user',
    entityId: users[0],
    operation: 'update',
    payload: { nickname: 'wrong-cell' },
    eventId: 'replication-event-wrong-cell'
  });
  assert.strictEqual(fenced.status, 'fenced');

  const second = nodeB.submit({
    entityType: 'user',
    entityId: users[4],
    operation: 'update',
    payload: { nickname: 'cell-b' },
    eventId: 'replication-event-2'
  });
  assert.strictEqual(second.status, 'applied');
  replicateShard(nodeB, nodeA, 4);
  const both = replicateOwnedShards(nodeA, nodeB);
  assert.strictEqual(both.maxLag, 0);
  const bothB = replicateOwnedShards(nodeB, nodeA);
  assert.strictEqual(bothB.maxLag, 0);
  const critical = nodeA.submitPeerDurable({
    entityType: 'transfer',
    entityId: 'critical-replication-1',
    operation: 'claim',
    payload: { amount: '1.00' },
    eventId: 'critical-replication-event'
  }, nodeB);
  assert.strictEqual(critical.status, 'committed');
  assert.strictEqual(critical.committed, true);
  assert.strictEqual(critical.peerReplicated, true);
  const originalSave = nodeB.saveCursors;
  nodeB.saveCursors = () => { throw new Error('simulated peer ack loss'); };
  const pending = nodeA.submitPeerDurable({
    entityType: 'transfer',
    entityId: 'critical-replication-2',
    operation: 'claim',
    payload: { amount: '2.00' },
    eventId: 'critical-replication-pending'
  }, nodeB);
  nodeB.saveCursors = originalSave;
  assert.strictEqual(pending.status, 'pending-peer');
  assert.strictEqual(pending.committed, false);
  const retried = nodeA.submitPeerDurable({
    entityType: 'transfer',
    entityId: 'critical-replication-2',
    operation: 'claim',
    payload: { amount: '2.00' },
    eventId: 'critical-replication-pending'
  }, nodeB);
  assert.strictEqual(retried.status, 'committed');
  assert.strictEqual(nodeA.verify().eventCount, 4);
  assert.strictEqual(nodeB.verify().eventCount, 4);

  assert.throws(() => nodeA.takeoverAll(), /lease is held/);
  console.log('dual-cell-replication: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
