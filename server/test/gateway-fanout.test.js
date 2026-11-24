'use strict';

const assert = require('assert');
const { GatewayFanoutBus } = require('../lib/gateway-fanout');

async function main() {
  const calls = [];
  let failOnce = true;
  const bus = new GatewayFanoutBus({
    secret: 'test',
    retries: 1,
    fetchImpl: async (url, init) => {
      calls.push({ url, body: JSON.parse(init.body) });
      if (failOnce) {
        failOnce = false;
        return { ok: false, status: 503, json: async () => ({ ok: false, error: 'busy' }) };
      }
      return { ok: true, status: 200, json: async () => ({ ok: true, delivered: 2 }) };
    }
  });
  const result = await bus.publish({
    publishId: 'p-1',
    nodes: [
      { id: 'gw-a', endpoint: 'http://gw-a', userIds: ['u1', 'u2'] },
      { id: 'gw-b', endpoint: 'http://gw-b', userIds: ['u3'] }
    ],
    payload: { type: 'message', message: { id: 'm1' } }
  });
  assert.equal(result.ok, true);
  assert.equal(result.delivered, 4);
  assert.equal(calls.length, 3);
  assert.equal(calls[0].url, 'http://gw-a/__gateway/publish');
  assert.equal(calls[0].body.publishId, 'p-1');
  console.log('gateway-fanout: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
