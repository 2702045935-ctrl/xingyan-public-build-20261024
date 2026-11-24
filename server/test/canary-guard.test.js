'use strict';

const assert = require('assert');
const { CanaryGuard } = require('../lib/canary-guard');

function main() {
  const guard = new CanaryGuard({
    maxFailureRatio: 0.1,
    maxPending: 10,
    minSamples: 5
  });
  guard.observe({ scanned: 5, acked: 5, failed: 0 }, { snapshot: () => ({ pending: 0 }) });
  assert.equal(guard.snapshot().paused, false);
  guard.observe({ scanned: 2, acked: 0, failed: 2 }, { snapshot: () => ({ pending: 0 }) });
  assert.equal(guard.snapshot().paused, true);
  assert.equal(guard.snapshot().reason, 'gateway-failure-ratio-exceeded');
  guard.resume();
  assert.equal(guard.snapshot().paused, false);
  guard.observe({ scanned: 1, acked: 1, failed: 0 }, { snapshot: () => ({ pending: 11 }) });
  assert.equal(guard.snapshot().reason, 'outbox-pending-exceeded');
  console.log('canary-guard: passed');
}

main();
