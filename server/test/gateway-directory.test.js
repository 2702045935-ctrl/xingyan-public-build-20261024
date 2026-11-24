'use strict';

const assert = require('assert');
const { GatewayDirectory } = require('../lib/gateway-directory');

function main() {
  let clock = 1000;
  const directory = new GatewayDirectory({
    nodeTimeoutMs: 1000,
    defaultLeaseMs: 2000,
    now: () => clock
  });
  directory.register({ id: 'gw-a', capacity: 100, endpoint: 'http://a:1', cellId: 'cell-a' });
  directory.register({ id: 'gw-b', capacity: 100, endpoint: 'http://b:1', cellId: 'cell-b' });
  directory.heartbeat('gw-a', { connections: 20 });
  directory.heartbeat('gw-b', { connections: 80 });
  const picked = directory.pick('user-1');
  assert.ok(picked);
  assert.equal(picked.node.id, 'gw-a');

  const claim = directory.claim('user-1', 'gw-a', { leaseMs: 2000 });
  assert.equal(claim.ok, true);
  assert.equal(claim.claim.epoch, 1);
  assert.equal(directory.lookup('user-1').gatewayId, 'gw-a');
  assert.equal(directory.claim('user-1', 'gw-b').ok, false);

  clock += 500;
  assert.equal(directory.renew('user-1', 'gw-a', 2000).epoch, 1);
  assert.equal(directory.release('user-1', 'gw-a', 99), false);
  assert.equal(directory.release('user-1', 'gw-a', 1), true);
  assert.equal(directory.lookup('user-1'), null);

  directory.claim('user-2', 'gw-a', { leaseMs: 1000 });
  clock += 1500;
  assert.equal(directory.lookup('user-2'), null);
  assert.equal(directory.snapshot().expired, 1);
  console.log('gateway-directory: passed');
}

main();
