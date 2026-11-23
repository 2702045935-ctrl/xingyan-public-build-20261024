'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { buildExpandedFleetPlan } = require('../lib/physical-scale-target');

const root = path.resolve(__dirname, '..', '..');
const source = JSON.parse(fs.readFileSync(
  path.join(root, 'deploy', 'fleet', 'fleet-production.json'), 'utf8'
));

function added(id, host, domain, prefix, base) {
  return {
    id,
    host,
    failureDomain: domain,
    servicePrefix: prefix,
    dataRoot: '/opt/xingyan-dual-cell/physical-r1/stage/shards',
    ports: Array.from({ length: 7 }, (_, shard) => base + shard * 100)
  };
}

const target = buildExpandedFleetPlan(source, [
  added('cell-c', '192.0.2.60', 'provider-c-zone-a',
    'xingyan-dual-cell-c', 23080),
  added('cell-d', '192.0.2.61', 'provider-d-zone-a',
    'xingyan-dual-cell-d', 24080)
], {
  topologyId: 'generated-4cell',
  verifiedDomains: {
    'cell-a-43': 'provider-a-zone-a',
    'cell-b-192': 'provider-b-zone-a'
  }
});

assert.strictEqual(target.deploymentEligible, true);
assert.strictEqual(target.cells.length, 4);
assert.deepStrictEqual(
  target.cells.flatMap((cell) => cell.ownerShards).sort((a, b) => a - b),
  [0, 1, 2, 3, 4, 5, 6]
);
assert.throws(() => buildExpandedFleetPlan(source, [
  added('cell-c', '192.0.2.60', 'unverified', 'xingyan-dual-cell-c', 23080)
]), /unverified/);

console.log('physical-scale-target: passed');
