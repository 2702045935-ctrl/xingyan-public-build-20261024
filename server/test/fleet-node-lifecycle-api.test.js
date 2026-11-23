'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { createFleetControlHttp } = require('../lib/fleet-control-http');

const root = path.resolve(__dirname, '..', '..');
const source = JSON.parse(fs.readFileSync(
  path.join(root, 'deploy', 'fleet', 'fleet-production.json'),
  'utf8'
));
source.cells[0].failureDomain = 'provider-a-zone-a';
source.cells[1].failureDomain = 'provider-b-zone-a';

function node() {
  return {
    id: 'cell-c-203',
    host: '192.0.2.30',
    failureDomain: 'provider-c-zone-a',
    servicePrefix: 'xingyan-dual-cell-c',
    dataRoot: '/opt/xingyan-dual-cell/physical-r1/stage/shards',
    ports: [21080, 21180, 21280, 21380, 21480, 21580, 21680]
  };
}

async function main() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-node-api-'));
  const fleetFile = path.join(dir, 'current.json');
  const targetFile = path.join(dir, 'target.json');
  const requestFile = path.join(dir, 'migration-request.json');
  const stateFile = path.join(dir, 'migration-state.json');
  const auditFile = path.join(dir, 'migration-audit.jsonl');
  const configFile = path.join(dir, 'auto-scale.json');
  fs.writeFileSync(fleetFile, JSON.stringify(source));
  fs.writeFileSync(configFile, JSON.stringify({
    allowExplicitMigration: true,
    promoteOnSuccess: false
  }));
  process.env.PHYSICAL_FLEET_PLAN = fleetFile;
  process.env.PHYSICAL_FLEET_TARGET = targetFile;
  process.env.PHYSICAL_AUTO_SCALE_CONFIG = configFile;
  process.env.PHYSICAL_MIGRATION_REQUEST = requestFile;
  process.env.PHYSICAL_MIGRATION_STATE = stateFile;
  process.env.PHYSICAL_MIGRATION_AUDIT = auditFile;
  const handler = createFleetControlHttp({
    ok: (res, data) => {
      res.statusCode = 200;
      res.payload = { ok: true, data };
    },
    fail: (res, status, message, details) => {
      res.statusCode = status;
      res.payload = { ok: false, error: message, details };
    },
    readBody: async (req) => req.body || {},
    audit: () => {},
    writeJson: (file, value) => {
      fs.mkdirSync(path.dirname(file), { recursive: true });
      fs.writeFileSync(file, JSON.stringify(value, null, 2));
    },
    currentOps: () => ({ id: '1', username: 'admin', role: 'super' }),
    opsConfirmOk: (_admin, body) => body.confirmPassword === 'secret',
    root
  });
  const call = async (parts, method, body) => {
    const req = { body };
    const res = { statusCode: 0, payload: null };
    const handled = await handler(req, res, parts, method);
    assert.strictEqual(handled, true);
    return res;
  };

  let response = await call(['ops', 'fleet', 'nodes', 'add'], 'POST', {
    node: node()
  });
  assert.strictEqual(response.statusCode, 428);
  assert.ok(!fs.existsSync(targetFile));

  response = await call(['ops', 'fleet', 'nodes', 'add'], 'POST', {
    node: node(),
    confirmPassword: 'secret'
  });
  assert.strictEqual(response.statusCode, 200, JSON.stringify(response.payload));
  assert.strictEqual(response.payload.data.plan.cells.length, 3);
  assert.strictEqual(response.payload.data.validation.ok, true);

  response = await call(['ops', 'fleet', 'nodes', 'delete'], 'POST', {
    cellId: 'cell-c-203',
    confirmPassword: 'secret'
  });
  assert.strictEqual(response.statusCode, 200, JSON.stringify(response.payload));
  assert.strictEqual(response.payload.data.plan.cells.length, 2);

  response = await call(['ops', 'fleet', 'nodes', 'rebalance'], 'POST', {
    confirmPassword: 'secret'
  });
  assert.strictEqual(response.statusCode, 200);

  response = await call(['ops', 'fleet', 'migration'], 'POST', {
    plan: response.payload.data.plan,
    confirmPassword: 'secret'
  });
  assert.strictEqual(response.statusCode, 200, JSON.stringify(response.payload));
  assert.strictEqual(response.payload.data.reason, 'migration-queued');
  assert.ok(fs.existsSync(requestFile));

  response = await call(['ops', 'fleet', 'migration'], 'GET');
  assert.strictEqual(response.statusCode, 200);
  assert.strictEqual(response.payload.data.state.status, 'awaiting-worker');

  fs.rmSync(dir, { recursive: true, force: true });
  console.log('fleet-node-lifecycle-api: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
