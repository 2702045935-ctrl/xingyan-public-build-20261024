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

async function call(base, method, url, body) {
  const response = await fetch(base + url, {
    method,
    headers: { 'Content-Type': 'application/json', 'x-device-kind': 'phone' },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await response.text();
  let payload = {};
  try { payload = text ? JSON.parse(text) : {}; } catch (_) {}
  return {
    status: response.status,
    data: payload.data === undefined ? payload : payload.data
  };
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-account-register-'));
  const port = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  let child;

  try {
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({ users: [] }));
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({ sliderLogin: 0 }));
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }));

    child = spawn(process.execPath, ['server.js'], {
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

    let ready = false;
    for (let i = 0; i < 120; i += 1) {
      if (child.exitCode !== null) throw new Error(logs.join(''));
      try {
        if ((await fetch(base + '/api/health')).ok) { ready = true; break; }
      } catch (_) {}
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    assert.equal(ready, true, 'server start timeout');

    const phone = '13800002001';
    let result = await call(base, 'POST', '/api/login/phone-code', {
      phone,
      register: true
    });
    assert.equal(result.status, 200, JSON.stringify(result.data));
    const code = String(result.data.devCode || '');
    assert.match(code, /^\d{6}$/);

    result = await call(base, 'POST', '/api/register', {
      username: 'legacy_account_name',
      nickname: '老用户账号',
      password: 'test123456',
      phone,
      code,
      requirePhoneCode: true,
      quick: true,
      captchaId: '',
      captcha: ''
    });
    assert.equal(result.status, 200, JSON.stringify(result.data));
    assert.equal(result.data.user.username, 'legacy_account_name');

    result = await call(base, 'POST', '/api/login', {
      username: 'legacy_account_name',
      password: 'test123456'
    });
    assert.equal(result.status, 200, JSON.stringify(result.data));

    console.log('account-registration-sms: passed');
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
