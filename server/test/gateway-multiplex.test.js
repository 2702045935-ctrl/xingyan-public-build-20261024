'use strict';

const assert = require('assert');
const {
  VirtualGatewaySocket,
  envelope,
  decodeEnvelope
} = require('../lib/gateway-multiplex');

function main() {
  const raw = envelope('data', 'conn-1', { data: 'AAEC' });
  const decoded = decodeEnvelope(raw);
  assert.equal(decoded.type, 'data');
  assert.equal(decoded.connectionId, 'conn-1');
  assert.equal(decoded.data, 'AAEC');

  const writes = [];
  let closeCount = 0;
  const socket = new VirtualGatewaySocket({
    connectionId: 'conn-1',
    remoteAddress: '127.0.0.1',
    onWrite: (value) => {
      writes.push(value.toString());
      return true;
    },
    onClose: () => { closeCount += 1; }
  });
  socket.on('data', () => {});
  assert.equal(socket.write('hello'), true);
  assert.equal(writes[0], 'hello');
  socket.end();
  socket.destroy();
  assert.equal(socket.destroyed, true);
  assert.equal(closeCount, 1);
  console.log('gateway-multiplex: passed');
}

main();
