'use strict';

const assert = require('assert');
const { EtcdSessionOwnership } = require('../lib/session-ownership-etcd');

function fakeEtcd() {
  const rows = new Map();
  let index = 0;
  return {
    rows,
    requestImpl: async (method, rawUrl, body) => {
      const url = new URL(rawUrl);
      const key = decodeURIComponent(url.pathname);
      const current = rows.get(key);
      if (method === 'GET') {
        if (!current) return { status: 404, body: null };
        return { status: 200, body: { node: { value: current.value, ttl: 30 } } };
      }
      if (method === 'PUT') {
        if (url.searchParams.get('prevExist') === 'false' && current) {
          return { status: 412, body: null };
        }
        const prev = url.searchParams.get('prevValue');
        if (prev != null && (!current || current.value !== prev)) return { status: 412, body: null };
        const params = new URLSearchParams(String(body || ''));
        index += 1;
        rows.set(key, { value: String(params.get('value') || ''), index });
        return { status: current || prev != null ? 200 : 201, body: {} };
      }
      if (method === 'DELETE') {
        if (!current) return { status: 404, body: null };
        rows.delete(key);
        return { status: 200, body: {} };
      }
      return { status: 405, body: null };
    }
  };
}

async function main() {
  const fake = fakeEtcd();
  const own = new EtcdSessionOwnership({
    prefix: '/test/sessions',
    requestImpl: fake.requestImpl
  });
  const a = await own.claim('u1', 'phone', 'gw-a');
  assert.equal(a.ok, true);
  assert.equal(a.claim.epoch, 1);
  assert.equal((await own.lookup('u1', 'phone')).gatewayId, 'gw-a');
  assert.equal((await own.claim('u1', 'phone', 'gw-b')).ok, false);
  assert.equal(await own.release('u1', 'phone', 'gw-a', 99), false);
  assert.equal(await own.release('u1', 'phone', 'gw-a', 1), true);
  const b = await own.claim('u1', 'tablet', 'gw-b');
  assert.equal(b.ok, true);
  assert.equal(b.claim.epoch, 2);
  console.log('session-ownership-etcd: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
