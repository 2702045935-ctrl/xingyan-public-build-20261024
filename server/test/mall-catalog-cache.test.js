'use strict';

const assert = require('assert');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const SERVER_DIR = path.resolve(__dirname, '..');

function freePort() {
  return new Promise((resolve, reject) => {
    const socket = net.createServer();
    socket.once('error', reject);
    socket.listen(0, '127.0.0.1', () => {
      const port = socket.address().port;
      socket.close(() => resolve(port));
    });
  });
}

async function waitForHealth(base, child, logs) {
  for (let i = 0; i < 120; i++) {
    if (child.exitCode !== null) {
      throw new Error('mall cache server exited:\n' + logs.join(''));
    }
    try {
      const response = await fetch(base + '/api/health');
      if (response.ok) return;
    } catch (_) {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('mall cache server start timeout:\n' + logs.join(''));
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-mall-cache-'));
  const port = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const mallFile = path.join(dataDir, 'mall.json');
  const logs = [];
  let child;

  try {
    fs.writeFileSync(mallFile, JSON.stringify({
      products: Array.from({ length: 128 }, (_, index) => ({
        id: 'cache-product-' + index,
        em: '📦',
        title: 'Cache Product ' + index,
        price: 19.9,
        orig: 39.9,
        sold: '1万',
        grp: 2,
        tags: ['包邮'],
        shop: 'Cache Shop',
        cate: '测试',
        on: true
      })),
      banners: [],
      categories: ['测试']
    }, null, 2));

    child = spawn(process.execPath, ['server.js'], {
      cwd: SERVER_DIR,
      env: Object.assign({}, process.env, {
        DATA_DIR: dataDir,
        PORT: String(port),
        TURN_PORT: String(turnPort),
        CHRIS_LOCAL_ONLY: '1'
      }),
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });
    child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
    child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
    await waitForHealth(base, child, logs);

    const first = await fetch(base + '/api/mall', {
      headers: { 'Accept-Encoding': 'gzip' }
    });
    assert.equal(first.status, 200);
    const etag = first.headers.get('etag');
    assert.ok(etag, 'mall catalog must expose ETag');
    assert.match(
      first.headers.get('cache-control') || '',
      /stale-while-revalidate/
    );
    const firstData = await first.json();
    assert.equal(firstData.data.products.length, 128);

    const cached = await fetch(base + '/api/mall', {
      headers: {
        'Accept-Encoding': 'gzip',
        'If-None-Match': etag
      }
    });
    assert.equal(cached.status, 304, 'matching ETag must avoid resending catalog');

    const mall = JSON.parse(fs.readFileSync(mallFile, 'utf8'));
    mall.products[0].title = 'Cache Product Changed';
    fs.writeFileSync(mallFile, JSON.stringify(mall, null, 2));
    await new Promise((resolve) => setTimeout(resolve, 20));

    const changed = await fetch(base + '/api/mall', {
      headers: { 'Accept-Encoding': 'gzip' }
    });
    assert.equal(changed.status, 200);
    assert.notEqual(changed.headers.get('etag'), etag);
    const changedData = await changed.json();
    assert.equal(changedData.data.products[0].title, 'Cache Product Changed');

    console.log('mall-catalog-cache: passed');
  } finally {
    if (child && child.exitCode === null) {
      child.kill('SIGTERM');
      await new Promise((resolve) => child.once('exit', resolve));
    }
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
