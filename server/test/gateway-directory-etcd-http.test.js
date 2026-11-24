'use strict';

const assert = require('assert');
const http = require('http');
const { EtcdGatewayDirectory } = require('../lib/gateway-directory-etcd');

function fakeEtcd() {
  const rows = new Map();
  let index = 0;
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://127.0.0.1');
    const key = decodeURIComponent(url.pathname);
    const current = rows.get(key);
    const send = (status, value) => {
      res.writeHead(status, { 'content-type': 'application/json' });
      res.end(JSON.stringify(value));
    };
    if (req.method === 'GET') {
      if (url.searchParams.get('recursive') === 'true') {
        const prefix = key.replace(/\/+$/, '') + '/';
        return send(200, {
          node: {
            nodes: Array.from(rows.entries())
              .filter(([name]) => name.startsWith(prefix))
              .map(([name, row]) => ({ key: name, value: row.value }))
          }
        });
      }
      if (!current) return send(404, null);
      return send(200, { node: { value: current.value, ttl: 30, modifiedIndex: current.index } });
    }
    if (req.method === 'PUT') {
      const body = [];
      req.on('data', (chunk) => body.push(chunk));
      req.on('end', () => {
        if (url.searchParams.get('prevExist') === 'false' && current) {
          return send(412, null);
        }
        const prev = url.searchParams.get('prevValue');
        if (prev != null && (!current || current.value !== prev)) return send(412, null);
        const params = new URLSearchParams(Buffer.concat(body).toString());
        index += 1;
        rows.set(key, { value: String(params.get('value') || ''), index });
        return send(current || prev != null ? 200 : 201, { action: 'set' });
      });
      return;
    }
    if (req.method === 'DELETE') {
      if (!current) return send(404, null);
      rows.delete(key);
      return send(200, { action: 'delete' });
    }
    return send(405, null);
  });
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => resolve({
      server,
      baseUrl: `http://127.0.0.1:${server.address().port}`
    }));
  });
}

async function main() {
  const fake = await fakeEtcd();
  const directory = new EtcdGatewayDirectory({
    baseUrl: fake.baseUrl,
    prefix: '/test/gateways',
    nodeTtlSeconds: 30,
    claimTtlSeconds: 30
  });
  await directory.register({ id: 'gw-http-a', capacity: 100 });
  await directory.register({ id: 'gw-http-b', capacity: 100 });
  assert.equal((await directory.listNodes()).length, 2);
  const claim = await directory.claim('http-user', 'gw-http-a');
  assert.equal(claim.ok, true);
  assert.equal((await directory.lookup('http-user')).gatewayId, 'gw-http-a');
  assert.equal(await directory.release('http-user', 'gw-http-a', 99), false);
  assert.equal(await directory.release('http-user', 'gw-http-a', claim.claim.epoch), true);
  fake.server.close();
  console.log('gateway-directory-etcd-http: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
