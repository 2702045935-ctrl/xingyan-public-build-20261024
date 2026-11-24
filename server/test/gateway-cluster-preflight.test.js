'use strict';

const assert = require('assert');
const http = require('http');
const path = require('path');
const { spawn } = require('child_process');

function listen(handler) {
  return new Promise((resolve) => {
    const server = http.createServer(handler);
    server.listen(0, '127.0.0.1', () => resolve({
      server,
      port: server.address().port
    }));
  });
}

async function main() {
  const backend = await listen((req, res) => {
    if (req.url === '/api/health') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ ok: true, data: { ok: true } }));
      return;
    }
    if (req.url === '/__gateway/directory'
        && req.headers['x-gateway-admin-secret'] === 'preflight-secret') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({
        ok: true,
        data: {
          directory: {
            mode: 'etcd',
            liveNodes: 2,
            nodes: [{ id: 'gw-a' }, { id: 'gw-b' }]
          }
        }
      }));
      return;
    }
    res.writeHead(403);
    res.end();
  });
  const gateway = await listen((req, res) => {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ ok: true, upstreamReady: true, clients: 0 }));
  });
  const tool = path.join(__dirname, '..', 'tools', 'gateway-cluster-preflight.js');
  const child = spawn(process.execPath, [
    tool,
    `--backend=http://127.0.0.1:${backend.port}`,
    '--secret=preflight-secret',
    '--directory-backend=etcd',
    '--fanout-mode=canary',
    '--canary-percent=1',
    `--gateways=http://127.0.0.1:${gateway.port},http://127.0.0.1:${gateway.port}`
  ], { stdio: ['ignore', 'pipe', 'pipe'] });
  let stdout = '';
  let stderr = '';
  child.stdout.on('data', (chunk) => { stdout += chunk.toString(); });
  child.stderr.on('data', (chunk) => { stderr += chunk.toString(); });
  const result = await new Promise((resolve) => {
    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      resolve({ status: -1, stdout, stderr: stderr + '\ntimeout' });
    }, 15000);
    child.on('close', (status) => {
      clearTimeout(timer);
      resolve({ status, stdout, stderr });
    });
  });
  backend.server.close();
  gateway.server.close();
  assert.equal(result.status, 0, result.stderr || result.stdout);
  const report = JSON.parse(result.stdout.trim().split('\n').pop());
  assert.equal(report.ok, true);
  assert.equal(report.directory.liveNodes, 2);
  console.log('gateway-cluster-preflight: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
