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
  for (let index = 0; index < 120; index += 1) {
    if (child.exitCode !== null) {
      throw new Error('测试服务提前退出：\n' + logs.join(''));
    }
    try {
      const response = await fetch(base + '/api/health');
      if (response.ok) return;
    } catch (_) {
      // 等待服务启动。
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('测试服务启动超时：\n' + logs.join(''));
}

async function checkPolicy(policy, expected) {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-call-policy-'));
  const port = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];

  fs.writeFileSync(path.join(dataDir, 'branding.json'), JSON.stringify({
    branding: policy === undefined ? {} : { callMediaPolicy: policy }
  }));
  fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({ sliderLogin: 0 }));
  fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }));

  const child = spawn(process.execPath, ['server.js'], {
    cwd: SERVER_DIR,
    env: Object.assign({}, process.env, {
      DATA_DIR: dataDir,
      PORT: String(port),
      TURN_PORT: String(turnPort),
      CHRIS_LOCAL_ONLY: '1',
      AML_RUNTIME_ENABLED: '0',
      DISABLE_STARTUP_BOT_BACKFILL: '1'
    }),
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true
  });
  child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
  child.stderr.on('data', (chunk) => logs.push(chunk.toString()));

  try {
    await waitForHealth(base, child, logs);
    const response = await fetch(base + '/api/branding');
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.data.branding.callMediaPolicy, expected);
  } finally {
    if (child.exitCode === null) {
      const exited = new Promise((resolve) => child.once('exit', resolve));
      child.kill();
      await Promise.race([
        exited,
        new Promise((resolve) => setTimeout(resolve, 3000))
      ]);
    }
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

async function main() {
  await checkPolicy(undefined, 'auto');
  await checkPolicy('self_hosted', 'self_hosted');
  await checkPolicy('tencent', 'tencent');
  await checkPolicy('unexpected-value', 'auto');
  console.log('call-media-policy: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
