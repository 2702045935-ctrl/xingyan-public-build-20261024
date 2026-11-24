'use strict';

const fs = require('fs');
const path = require('path');
const { runGatewayClusterDrill } = require('../lib/gateway-cluster-drill');

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const found = process.argv.find((value) => value.startsWith(prefix));
  return found ? found.slice(prefix.length) : fallback;
}

async function main() {
  const report = await runGatewayClusterDrill({
    members: Number(arg('members', '10000'))
  });
  const out = path.resolve(arg('out', 'gateway-cluster-drill.json'));
  fs.writeFileSync(out, JSON.stringify(report, null, 2) + '\n', 'utf8');
  console.log(JSON.stringify(report));
  if (!report.ok) process.exitCode = 1;
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
