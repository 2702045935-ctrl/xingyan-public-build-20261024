'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { HotGroupRouter } = require('./hot-group-router');
const { FanoutOutbox } = require('./fanout-outbox');
const { FanoutDispatcher } = require('./fanout-dispatcher');

async function runGatewayClusterDrill(options) {
  const opts = options || {};
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-gateway-drill-'));
  let clock = 1000;
  const outbox = new FanoutOutbox({
    file: path.join(dir, 'outbox.jsonl'),
    now: () => clock
  });
  const router = new HotGroupRouter({
    threshold: 512,
    maxBatch: 128,
    cellCount: 7
  });
  const members = Array.from({ length: Number(opts.members) || 10_000 },
    (_, index) => `u-${index}`);
  const plan = router.plan({
    chatId: 'cluster-drill-group',
    memberIds: members,
    nodeIds: ['gw-a', 'gw-b', 'gw-c']
  });
  const nodes = plan.batches.map((batch) => ({
    id: batch.nodeId,
    endpoint: `http://${batch.nodeId}`,
    userIds: batch.userIds
  }));
  let failedOnce = false;
  const calls = [];
  const dispatcher = new FanoutDispatcher({
    outbox,
    maxBackoffMs: 1000,
    now: () => clock,
    bus: {
      async publish(input) {
        calls.push(input);
        if (!failedOnce && input.nodes.some((node) => node.id === 'gw-b')) {
          failedOnce = true;
          return {
            ok: false,
            delivered: 0,
            results: [{ nodeId: 'gw-b', ok: false, error: 'simulated-node-down' }]
          };
        }
        return { ok: true, delivered: input.nodes.reduce(
          (sum, node) => sum + node.userIds.length, 0
        ), results: input.nodes.map((node) => ({ nodeId: node.id, ok: true })) };
      }
    }
  });
  outbox.enqueue({
    publishId: 'cluster-drill-1',
    chatId: 'cluster-drill-group',
    payload: { type: 'message', message: { id: 'm-drill' } },
    nodes
  });
  const first = await dispatcher.flush({ limit: 10 });
  const pendingAfterFailure = outbox.snapshot().pending;
  clock += 2000;
  const second = await dispatcher.flush({ limit: 10 });
  const snapshot = outbox.snapshot();
  const report = {
    ok: first.failed === 1 && pendingAfterFailure === 1
      && second.acked === 1 && snapshot.pending === 0,
    members: members.length,
    batches: plan.batches.length,
    nodes: nodes.map((node) => node.id),
    firstFlush: first,
    pendingAfterFailure,
    secondFlush: second,
    finalPending: snapshot.pending,
    finalAcked: snapshot.acked,
    retryAttempts: Math.max(0, calls.length - 1)
  };
  fs.rmSync(dir, { recursive: true, force: true });
  return report;
}

module.exports = { runGatewayClusterDrill };
