'use strict';

const assert = require('assert');
const { SessionOwnership } = require('../lib/session-ownership');
const { GatewaySessionLeaseAgent } = require('../lib/gateway-session-lease-agent');

function harness(options) {
  const opts = options || {};
  let clock = 1000;
  const ownership = new SessionOwnership({
    defaultLeaseMs: 9000,
    now: () => clock
  });
  const clients = [
    { connectionId: 'c1', userId: 'u1', socket: { destroy() { this.destroyed = true; } } },
    { connectionId: 'c2', userId: 'u2', socket: { destroy() { this.destroyed = true; } } },
    { connectionId: 'c3', userId: 'u3', socket: { destroy() { this.destroyed = true; } } }
  ];
  for (const client of clients) ownership.claim(client.userId, client.connectionId, 'gw-a');
  const sessions = { all: () => clients };
  const closed = [];
  const agent = new GatewaySessionLeaseAgent({
    sessions,
    ownership,
    gatewayId: 'gw-a',
    leaseMs: 9000,
    remoteBatchSize: 2,
    remoteRenew: opts.remoteRenew,
    now: () => clock,
    closeClient: (client, reason) => {
      closed.push({ connectionId: client.connectionId, reason });
      client.socket.destroy();
    }
  });
  return {
    clients,
    closed,
    ownership,
    agent,
    advance(ms) { clock += ms; }
  };
}

async function testRemoteRenewal() {
  const batches = [];
  const h = harness({
    remoteRenew: async (rows) => {
      batches.push(rows);
      return rows.map((row) => row.connectionId === 'c3'
        ? { ok: true, claim: null }
        : { ok: true, claim: { epoch: 1, expiresAt: Date.now() + 9000 } });
    }
  });
  await h.agent.renewOnce();
  assert.deepStrictEqual(batches.map((batch) => batch.length), [2, 1]);
  assert.equal(h.closed.length, 1);
  assert.equal(h.closed[0].connectionId, 'c3');
  assert.equal(h.agent.snapshot().remoteRenewed, 2);
  assert.equal(h.agent.snapshot().remoteLost, 1);
}

async function testRemoteFailureGraceThenClose() {
  let fail = true;
  const h = harness({
    remoteRenew: async (rows) => {
      if (fail) throw new Error('etcd unavailable');
      return rows.map(() => ({
        ok: true,
        claim: { epoch: 1, expiresAt: Date.now() + 9000 }
      }));
    }
  });
  await h.agent.renewOnce();
  assert.equal(h.closed.length, 0, 'one transient failure must not disconnect clients');
  fail = false;
  await h.agent.renewOnce();
  assert.equal(h.closed.length, 0);
  assert.equal(h.agent.snapshot().remoteFailures, 2);
  assert.equal(h.clients[0].remoteFailureSince, 0);

  fail = true;
  await h.agent.renewOnce();
  h.advance(7000);
  await h.agent.renewOnce();
  assert.equal(h.closed.length, 3, 'persistent remote failure must fail closed');
}

async function testLocalLeaseLossClosesClient() {
  const h = harness();
  h.ownership.release('u2', 'c2', 'gw-a');
  await h.agent.renewOnce();
  assert.equal(h.closed.length, 1);
  assert.equal(h.closed[0].connectionId, 'c2');
  assert.equal(h.closed[0].reason, 'local-session-lease-lost');
}

async function main() {
  await testRemoteRenewal();
  await testRemoteFailureGraceThenClose();
  await testLocalLeaseLossClosesClient();
  console.log('gateway-session-lease-agent: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
