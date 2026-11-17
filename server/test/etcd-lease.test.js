'use strict';

const assert = require('assert');
const { EtcdLeaseManager } = require('../lib/etcd-lease');

function fakeEtcd(startedAt) {
  let clock = startedAt || 1000;
  const rows = new Map();
  let index = 0;
  const now = () => clock;
  const requestImpl = async (method, rawUrl, body) => {
    const url = new URL(rawUrl);
    const key = decodeURIComponent(url.pathname);
    const isEpoch = key.indexOf('/epochs/') >= 0;
    const current = rows.get(key);
    const live = current && (isEpoch || Number(current.expiresAt) > clock) ? current : null;
    if (method === 'GET') {
      if (!live) return { status: 404, body: null };
      return {
        status: 200,
        body: {
          node: {
            value: live.value,
            ttl: isEpoch ? 0 : Math.max(0, Math.ceil((live.expiresAt - clock) / 1000)),
            modifiedIndex: live.modifiedIndex
          }
        }
      };
    }
    if (method === 'PUT') {
      const prevValue = url.searchParams.get('prevValue');
      const prevExist = url.searchParams.get('prevExist');
      if (prevExist === 'false' && live) return { status: 412, body: null };
      if (prevValue != null && (!live || live.value !== prevValue)) {
        return { status: 412, body: null };
      }
      const params = new URLSearchParams(String(body || ''));
      const value = String(params.get('value') || '');
      const ttl = isEpoch ? 0 : Math.max(1, Number(url.searchParams.get('ttl')) || 1);
      index += 1;
      rows.set(key, {
        value,
        expiresAt: isEpoch ? Infinity : clock + ttl * 1000,
        modifiedIndex: index
      });
      return { status: current ? 200 : 201, body: { action: 'set', node: { value } } };
    }
    if (method === 'DELETE') {
      const prevValue = url.searchParams.get('prevValue');
      if (!live) return { status: 404, body: null };
      if (prevValue != null && live.value !== prevValue) return { status: 412, body: null };
      rows.delete(key);
      return { status: 200, body: { action: 'delete' } };
    }
    return { status: 405, body: null };
  };
  return {
    requestImpl,
    now,
    advance: (ms) => { clock += ms; },
    rows
  };
}

async function main() {
  const fake = fakeEtcd();
  const a = new EtcdLeaseManager({
    prefix: '/test/leases',
    ownerId: 'cell-a',
    ttlMs: 3000,
    requestImpl: fake.requestImpl
  });
  const b = new EtcdLeaseManager({
    prefix: '/test/leases',
    ownerId: 'cell-b',
    ttlMs: 3000,
    requestImpl: fake.requestImpl
  });
  const first = await a.acquire(0);
  assert.strictEqual(first.epoch, 1);
  assert.strictEqual((await a.validate(0)).ok, true);
  await assert.rejects(() => b.acquire(0), /held by cell-a/);

  fake.advance(4000);
  const second = await b.acquire(0);
  assert.strictEqual(second.epoch, 2);
  assert.strictEqual((await a.validate(0)).reason, 'not-owner');
  assert.strictEqual(await a.release(0), false, 'old owner must not release new lease');
  assert.strictEqual((await b.validate(0)).ok, true);
  const renewed = await b.renew(0);
  assert.strictEqual(renewed.epoch, 2);
  assert.strictEqual(await b.release(0), true);
  assert.strictEqual((await b.validate(0)).ok, false);

  console.log('etcd-lease: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
