'use strict';

const assert = require('assert');
const { EtcdGatewayDirectory } = require('../lib/gateway-directory-etcd');

function fakeEtcd() {
  const rows = new Map();
  let index = 0;
  const requestImpl = async (method, rawUrl, body) => {
    const url = new URL(rawUrl);
    const key = decodeURIComponent(url.pathname);
    const current = rows.get(key);
    if (method === 'GET') {
      if (url.searchParams.get('recursive') === 'true') {
        const prefix = key.replace(/\/+$/, '') + '/';
        const nodes = Array.from(rows.entries())
          .filter(([rowKey]) => rowKey.startsWith(prefix))
          .map(([rowKey, row]) => ({ key: rowKey, value: row.value }));
        return { status: 200, body: { node: { nodes } } };
      }
      if (!current) return { status: 404, body: null };
      return {
        status: 200,
        body: {
          node: {
            value: current.value,
            ttl: 30,
            modifiedIndex: current.index
          }
        }
      };
    }
    if (method === 'PUT') {
      const prev = url.searchParams.get('prevValue');
      if (prev != null && (!current || current.value !== prev)) {
        return { status: 412, body: null };
      }
      if (url.searchParams.get('prevExist') === 'false' && current) {
        return { status: 412, body: null };
      }
      const params = new URLSearchParams(String(body || ''));
      index += 1;
      rows.set(key, {
        value: String(params.get('value') || ''),
        index
      });
      return { status: current ? 200 : 201, body: { action: 'set' } };
    }
    if (method === 'DELETE') {
      if (!current) return { status: 404, body: null };
      rows.delete(key);
      return { status: 200, body: { action: 'delete' } };
    }
    return { status: 405, body: null };
  };
  return { requestImpl, rows };
}

async function main() {
  const fake = fakeEtcd();
  const directory = new EtcdGatewayDirectory({
    requestImpl: fake.requestImpl,
    prefix: '/test/gateways'
  });
  await directory.register({ id: 'gw-a', capacity: 100 });
  await directory.register({ id: 'gw-b', capacity: 100 });
  assert.equal((await directory.listNodes()).length, 2);

  const claim = await directory.claim('u1', 'gw-a');
  assert.equal(claim.ok, true);
  assert.equal(claim.claim.epoch, 1);
  assert.equal((await directory.lookup('u1')).gatewayId, 'gw-a');
  assert.equal((await directory.claim('u1', 'gw-b')).ok, false);
  assert.equal(await directory.release('u1', 'gw-a', 99), false);
  assert.equal(await directory.release('u1', 'gw-a', 1), true);
  assert.equal(await directory.lookup('u1'), null);

  const takeover = await directory.claim('u2', 'gw-a');
  const forced = await directory.claim('u2', 'gw-b', { force: true });
  assert.equal(takeover.ok, true);
  assert.equal(forced.ok, true);
  assert.equal(forced.claim.epoch, 2);
  console.log('gateway-directory-etcd: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
