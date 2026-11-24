'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const SERVER = path.join(ROOT, 'server.js');
const GATEWAY = path.join(ROOT, 'gateway-server.js');
const SECRET = 'gateway-smoke-secret';

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const found = process.argv.find((value) => value.startsWith(prefix));
  return found ? found.slice(prefix.length) : fallback;
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function getJson(url, options) {
  const response = await fetch(url, Object.assign({
    signal: AbortSignal.timeout(1500)
  }, options || {}));
  if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`);
  return response.json();
}

async function waitFor(url, predicate, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  let last = null;
  while (Date.now() < deadline) {
    try {
      const data = await getJson(url);
      last = data;
      if (!predicate || predicate(data)) return data;
    } catch (error) {
      last = String(error && error.message || error);
    }
    await wait(300);
  }
  throw new Error(`timeout waiting for ${url}: ${last}`);
}

function child(name, script, env) {
  const proc = spawn(process.execPath, [script], {
    cwd: ROOT,
    env: Object.assign({}, process.env, env),
    windowsHide: true,
    stdio: ['ignore', 'pipe', 'pipe']
  });
  const logs = [];
  proc.stdout.on('data', (chunk) => logs.push(chunk.toString()));
  proc.stderr.on('data', (chunk) => logs.push(chunk.toString()));
  return { name, process: proc, logs };
}

async function stop(item) {
  if (!item) return;
  try { item.process.kill('SIGTERM'); } catch (_) { /* already gone */ }
  await wait(500);
  try { item.process.kill('SIGKILL'); } catch (_) { /* already gone */ }
}

async function main() {
  const base = Number(arg('base-port', '5210'));
  const gatewayBase = Number(arg('gateway-port', '5292'));
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-gateway-smoke-'));
  const children = [];
  try {
    const backendEnv = {
      DATA_DIR: dataDir,
      PORT: String(base),
      GATEWAY_ADMIN_SECRET: SECRET,
      GATEWAY_DIRECTORY_BACKEND: 'local',
      AML_RUNTIME_ENABLED: '0',
      PAYMENT_DATABASE_MODE: 'legacy'
    };
    const backend = child('backend', SERVER, backendEnv);
    children.push(backend);
    await waitFor(`http://127.0.0.1:${base}/api/health`,
      (data) => data && data.ok === true, 15000);

    for (let index = 0; index < 2; index += 1) {
      const port = gatewayBase + index;
      const gateway = child(`gateway-${index + 1}`, GATEWAY, {
        GATEWAY_PORT: String(port),
        GATEWAY_HOST: '127.0.0.1',
        GATEWAY_UPSTREAM_WS: `ws://127.0.0.1:${base}/__gateway/upstream`,
        GATEWAY_BACKEND_HTTP: `http://127.0.0.1:${base}`,
        GATEWAY_ADMIN_SECRET: SECRET,
        GATEWAY_NODE_ID: `smoke-gateway-${index + 1}`,
        GATEWAY_CELL_ID: `smoke-cell-${index + 1}`
      });
      children.push(gateway);
      await waitFor(`http://127.0.0.1:${port}/health`,
        (data) => data && data.ok === true && data.upstreamReady === true, 15000);
    }

    const directory = await getJson(
      `http://127.0.0.1:${base}/__gateway/directory`,
      { headers: { 'X-Gateway-Admin-Secret': SECRET } }
    );
    const report = {
      ok: directory.data.directory.liveNodes >= 2,
      basePort: base,
      gatewayPorts: [gatewayBase, gatewayBase + 1],
      liveNodes: directory.data.directory.liveNodes,
      nodes: directory.data.directory.nodes.map((node) => ({
        id: node.id,
        cellId: node.cellId,
        endpoint: node.endpoint
      }))
    };
    console.log(JSON.stringify(report));
    if (!report.ok) process.exitCode = 1;
  } catch (error) {
    for (const item of children) {
      if (item.logs.length) console.error(`[${item.name}]\n${item.logs.join('')}`);
    }
    throw error;
  } finally {
    for (const item of children) await stop(item);
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
