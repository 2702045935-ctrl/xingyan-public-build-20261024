'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..', '..');

function env(file) {
  const values = {};
  fs.readFileSync(path.join(root, 'deploy', 'dual-cell', file), 'utf8')
    .split(/\r?\n/)
    .forEach((line) => {
      const match = line.match(/^([A-Z0-9_]+)=(.*)$/);
      if (match) values[match[1]] = match[2].trim();
    });
  return values;
}

function main() {
  const a = env('a.env');
  const b = env('b.env');
  const aCall = Number(a.CALL_SIGNAL_PORT);
  const bCall = Number(b.CALL_SIGNAL_PORT);
  const aBase = Number(a.DUAL_CELL_RUNTIME_BASE_PORT);
  const aOwners = String(a.DUAL_CELL_OWNER_PORTS || '').split(',').map(Number);

  assert.ok(aCall > 0, 'cell A must configure CALL_SIGNAL_PORT');
  assert.ok(bCall > 0, 'cell B must configure CALL_SIGNAL_PORT');
  assert.strictEqual(aCall, aBase,
    'cell A call signaling must live on shard 0');
  assert.ok(aOwners.includes(aCall),
    'cell A call-signal port must be an owner runtime port');

  const peers = fs.readFileSync(path.join(
    root, 'deploy', 'dual-cell', 'xingyan-dual-cell-b-peers.service'
  ), 'utf8');
  const tunnel = `127.0.0.1:${bCall}:127.0.0.1:${aCall}`;
  assert.ok(peers.includes(`-L ${tunnel}`),
    `cell B must tunnel ${bCall} to cell A ${aCall}`);
  assert.notStrictEqual(bCall, 7080,
    'cell B must not forward call signals to the non-listening legacy port 7080');

  const probe = fs.readFileSync(path.join(root, 'server', 'server.js'), 'utf8');
  assert.ok(probe.includes('callSignalReachable'),
    'health must expose call-signal reachability');
  assert.ok(probe.includes('通话服务暂时不可用'),
    'call forwarding failure must be reported to the client');

  console.log('dual-cell-call-topology: passed');
}

main();
