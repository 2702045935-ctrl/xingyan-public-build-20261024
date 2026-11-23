'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const SERVER_DIR = path.resolve(__dirname, '..');
const PASSWORD = 'TransferKernel1027!';

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

function sha256(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

async function uploadChunk(base, cookie, transfer, index, payload, digest) {
  const start = index * transfer.chunkSize;
  const end = Math.min(payload.length, start + transfer.chunkSize);
  return fetch(base + '/api/transfer/' + transfer.id + '/chunk', {
    method: 'POST',
    headers: {
      Cookie: cookie,
      'Content-Type': 'application/octet-stream',
      'x-transfer-chunk-index': String(index),
      'x-transfer-chunk-sha256': digest || sha256(payload.subarray(start, end))
    },
    body: payload.subarray(start, end)
  });
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-transfer-kernel-'));
  const port = await freePort();
  const httpsPort = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const salt = crypto.randomBytes(16).toString('hex');
  const logs = [];
  let child;

  try {
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [{
        id: 'u_transfer_kernel',
        username: 'transfer_kernel',
        nickname: 'Transfer kernel',
        phone: '',
        realName: '',
        gender: 'secret',
        balance: 0,
        transferLimit: 20000,
        salt,
        passwordHash: crypto.scryptSync(PASSWORD, salt, 64).toString('hex'),
        favorites: [],
        createdAt: new Date().toISOString(),
        tokenVersion: 0,
        phoneSession: 0
      }]
    }));
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({ sliderLogin: 0 }));
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }));

    child = spawn(process.execPath, ['server.js'], {
      cwd: SERVER_DIR,
      env: Object.assign({}, process.env, {
        DATA_DIR: dataDir,
        ENABLE_TRANSFER_KERNEL: '1',
        PORT: String(port),
        HTTPS_PORT: String(httpsPort),
        TURN_PORT: String(turnPort),
        ADMIN_PASSWORD: 'test-admin-password',
        CHRIS_LOCAL_ONLY: '1',
        SHARD_COUNT: '1'
      }),
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });
    child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
    child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
    for (let attempt = 0; attempt < 200; attempt += 1) {
      if (child.exitCode !== null) throw new Error('测试服务提前退出：\n' + logs.join(''));
      try {
        if ((await fetch(base + '/api/health')).ok) break;
      } catch (_) {
        // Wait for startup.
      }
      await new Promise((resolve) => setTimeout(resolve, 100));
    }

    const login = await fetch(base + '/api/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-device-kind': 'phone' },
      body: JSON.stringify({ username: 'transfer_kernel', password: PASSWORD })
    });
    assert.equal(login.status, 200, await login.text());
    const rawCookie = login.headers.getSetCookie
      ? login.headers.getSetCookie()[0]
      : login.headers.get('set-cookie') || '';
    const cookie = rawCookie.split(';')[0];

    const capabilityResponse = await fetch(base + '/api/transfer/capabilities', {
      headers: { Cookie: cookie }
    });
    const capability = await capabilityResponse.json();
    assert.equal(capabilityResponse.status, 200, JSON.stringify(capability));
    assert.equal(capability.data.version, 1);

    const requestedBytes = Number(process.env.XINGYAN_TRANSFER_TEST_BYTES || 0);
    const payloadBytes = Number.isSafeInteger(requestedBytes) && requestedBytes > 0
      ? requestedBytes
      : 9 * 1024 * 1024 + 123;
    const payload = crypto.randomBytes(payloadBytes);
    const digest = sha256(payload);
    const initResponse = await fetch(base + '/api/transfer/init', {
      method: 'POST',
      headers: { Cookie: cookie, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        size: payload.length,
        sha256: digest,
        mime: 'application/octet-stream',
        name: 'resume-test.bin',
        skipTranscode: true
      })
    });
    const initBody = await initResponse.json();
    assert.equal(initResponse.status, 200, JSON.stringify(initBody));
    let transfer = initBody.data.transfer;
    assert.ok(transfer.chunkSize >= 256 * 1024, 'chunk size must be bounded');
    assert.equal(transfer.totalChunks, Math.ceil(payload.length / transfer.chunkSize));
    assert.equal(transfer.processing.status, 'idle');

    const firstIndex = transfer.totalChunks - 1;
    const firstChunk = await uploadChunk(base, cookie, transfer, firstIndex, payload);
    const firstChunkBody = await firstChunk.json();
    assert.equal(firstChunk.status, 200, JSON.stringify(firstChunkBody));
    transfer = firstChunkBody.data;

    const resumedResponse = await fetch(base + '/api/transfer/' + transfer.id, {
      headers: { Cookie: cookie }
    });
    const resumedBody = await resumedResponse.json();
    assert.equal(resumedResponse.status, 200, JSON.stringify(resumedBody));
    transfer = resumedBody.data.transfer;
    const expectedMissing = Array.from(
      { length: transfer.totalChunks - 1 },
      (_, index) => index
    );
    assert.deepEqual(transfer.received, [firstIndex]);
    assert.deepEqual(transfer.missing, expectedMissing);

    const concurrentIndexes = expectedMissing.slice(0, 2);
    const concurrent = await Promise.all(
      concurrentIndexes.map((index) => uploadChunk(base, cookie, transfer, index, payload))
    );
    for (const response of concurrent) {
      const body = await response.json();
      assert.equal(response.status, 200, JSON.stringify(body));
    }

    const duplicateResponse = await uploadChunk(
      base,
      cookie,
      transfer,
      expectedMissing[0],
      payload
    );
    const duplicateBody = await duplicateResponse.json();
    assert.equal(duplicateResponse.status, 200, JSON.stringify(duplicateBody));
    assert.equal(duplicateBody.data.duplicate, true);

    const remaining = await Promise.all(
      expectedMissing
        .slice(concurrentIndexes.length)
        .map((index) => uploadChunk(base, cookie, transfer, index, payload))
    );
    for (const response of remaining) {
      const body = await response.json();
      assert.equal(response.status, 200, JSON.stringify(body));
    }

    const readyStatus = await fetch(base + '/api/transfer/' + transfer.id, {
      headers: { Cookie: cookie }
    });
    const readyStatusBody = await readyStatus.json();
    transfer = readyStatusBody.data.transfer;
    assert.equal(transfer.receivedBytes, payload.length);

    const completeResponse = await fetch(base + '/api/transfer/' + transfer.id + '/complete', {
      method: 'POST',
      headers: { Cookie: cookie, 'Content-Type': 'application/json' },
      body: '{}'
    });
    const completeBody = await completeResponse.json();
    assert.equal(completeResponse.status, 200, JSON.stringify(completeBody));
    transfer = completeBody.data.transfer;
    assert.equal(transfer.status, 'ready');
    assert.ok(transfer.url.startsWith('/uploads/xfer_'), JSON.stringify(transfer));

    const download = await fetch(base + transfer.url, { headers: { Cookie: cookie } });
    assert.equal(download.status, 200);
    const downloaded = Buffer.from(await download.arrayBuffer());
    assert.equal(downloaded.length, payload.length);
    assert.ok(downloaded.equals(payload), '续传完成后下载内容不一致');

    const uploadFiles = fs.readdirSync(path.join(dataDir, 'uploads'));
    assert.equal(uploadFiles.length, 1, '上传目录不应残留分片临时文件');
    const stored = fs.readFileSync(path.join(dataDir, 'uploads', uploadFiles[0]));
    assert.equal(stored.subarray(0, 4).toString('ascii'), 'LUC1');
    assert.ok(!stored.equals(payload), '最终文件必须加密落盘');

    const badPayload = crypto.randomBytes(512 * 1024);
    const badInitResponse = await fetch(base + '/api/transfer/init', {
      method: 'POST',
      headers: { Cookie: cookie, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        size: badPayload.length,
        sha256: sha256(badPayload),
        mime: 'application/octet-stream',
        name: 'bad-hash.bin'
      })
    });
    const badInitBody = await badInitResponse.json();
    assert.equal(badInitResponse.status, 200, JSON.stringify(badInitBody));
    const badTransfer = badInitBody.data.transfer;
    const badChunk = await uploadChunk(
      base,
      cookie,
      badTransfer,
      0,
      badPayload,
      '0'.repeat(64)
    );
    assert.equal(badChunk.status, 422, await badChunk.text());
    const badStatus = await fetch(base + '/api/transfer/' + badTransfer.id, {
      headers: { Cookie: cookie }
    });
    const badStatusBody = await badStatus.json();
    assert.deepEqual(badStatusBody.data.transfer.missing, [0]);

    console.log('transfer-kernel: passed');
  } finally {
    if (child && child.exitCode === null) child.kill();
    await new Promise((resolve) => setTimeout(resolve, 150));
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
