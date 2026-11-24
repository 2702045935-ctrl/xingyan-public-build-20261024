'use strict';

const assert = require('assert');
const { SessionCell } = require('../lib/session-cell');

function main() {
  const cell = new SessionCell({ maxConnections: 4 });
  const one = { socket: { id: 1 } };
  assert.equal(cell.open('c1', one).ok, true);
  assert.equal(cell.open('c1', one).ok, false);
  assert.equal(cell.bindUser('c1', 'u1'), true);
  assert.equal(cell.forUser('u1').length, 1);
  assert.equal(cell.open('c2', { socket: { id: 2 } }).ok, true);
  assert.equal(cell.bindUser('c2', 'u1'), true);
  assert.equal(cell.forUser('u1').length, 2);
  assert.equal(cell.close('c1'), true);
  assert.equal(cell.forUser('u1').length, 1);
  assert.equal(cell.snapshot().connections, 1);
  assert.equal(cell.snapshot().users, 1);
  cell.drain();
  assert.equal(cell.snapshot().draining, true);
  cell.resume();
  assert.equal(cell.snapshot().draining, false);
  console.log('session-cell: passed');
}

main();
