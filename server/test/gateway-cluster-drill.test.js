'use strict';

const assert = require('assert');
const { runGatewayClusterDrill } = require('../lib/gateway-cluster-drill');

async function main() {
  const report = await runGatewayClusterDrill({ members: 10_000 });
  assert.equal(report.ok, true);
  assert.equal(report.pendingAfterFailure, 1);
  assert.equal(report.finalPending, 0);
  assert.equal(report.finalAcked, 1);
  assert.equal(report.retryAttempts, 1);
  console.log('gateway-cluster-drill: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
