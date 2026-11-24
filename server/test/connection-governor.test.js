'use strict';

const assert = require('assert');
const { ConnectionGovernor } = require('../lib/connection-governor');

function main() {
  const governor = new ConnectionGovernor({
    maxTotal: 3,
    maxPerUser: 1,
    maxPerIp: 2,
    softLoadRatio: 0.66,
    now: (() => {
      let tick = 0;
      return () => ++tick;
    })(),
    uid: (() => {
      let seq = 0;
      return (prefix) => `${prefix}-${++seq}`;
    })()
  });

  const a = governor.admit({ userId: 'u1', ip: '10.0.0.1', kind: 'phone' });
  assert.equal(a.ok, true);
  assert.equal(governor.snapshot().total, 1);
  assert.equal(governor.snapshot().softLoaded, false);
  assert.equal(governor.admit({ userId: 'u1', ip: '10.0.0.2' }).reason, 'user-limit');
  const b = governor.admit({ userId: 'u2', ip: '10.0.0.1' });
  assert.equal(b.ok, true);
  assert.equal(governor.snapshot().softLoaded, true);
  assert.equal(governor.admit({ userId: 'u3', ip: '10.0.0.1' }).reason, 'ip-limit');
  assert.equal(governor.release(a.lease.id), true);
  assert.equal(governor.release(a.lease.id), false);
  assert.equal(governor.snapshot().total, 1);
  assert.equal(governor.drain().draining, true);
  assert.equal(governor.admit({ userId: 'u4', ip: '10.0.0.4' }).reason, 'draining');
  assert.equal(governor.resume().draining, false);
  assert.equal(governor.release(b.lease), true);
  assert.equal(governor.snapshot().total, 0);
  assert.equal(governor.snapshot().released, 2);
  console.log('connection-governor: passed');
}

main();
