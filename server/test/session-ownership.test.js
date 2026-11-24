'use strict';

const assert = require('assert');
const { SessionOwnership } = require('../lib/session-ownership');

function main() {
  let clock = 1000;
  const ownership = new SessionOwnership({
    defaultLeaseMs: 2000,
    now: () => clock
  });
  assert.equal(ownership.claim('u1', 'device-a', 'gw-1').ok, true);
  assert.equal(ownership.claim('u1', 'device-b', 'gw-2').ok, true);
  assert.equal(ownership.lookupUser('u1').length, 2);
  assert.equal(ownership.claim('u1', 'device-a', 'gw-2').ok, false);
  assert.equal(ownership.lookupConnection('u1', 'device-a').gatewayId, 'gw-1');
  clock += 500;
  assert.equal(ownership.renew('u1', 'device-a', 'gw-1', 2000).epoch, 1);
  assert.equal(ownership.release('u1', 'device-b', 'gw-2', 2), true);
  clock += 2500;
  assert.equal(ownership.lookupConnection('u1', 'device-a'), null);
  assert.equal(ownership.snapshot().expired >= 1, true);
  console.log('session-ownership: passed');
}

main();
