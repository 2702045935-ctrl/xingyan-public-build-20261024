#!/usr/bin/env node
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const row = process.argv.slice(2).find((value) => value.startsWith(prefix));
  return row ? row.slice(prefix.length) : fallback;
}

async function health(port) {
  const response = await fetch('http://127.0.0.1:' + port + '/api/health', {
    signal: AbortSignal.timeout(2500)
  });
  const payload = await response.json();
  return response.ok && payload && payload.ok === true;
}

async function main() {
  const cellId = String(arg('cell', ''));
  const ports = String(arg('ports', '')).split(',').map(Number).filter(Boolean);
  const dataRoot = path.resolve(arg('data-root', '/opt/xingyan-dual-cell'));
  if (!cellId || !ports.length) {
    throw new Error('usage: --cell=ID --ports=p1,p2 [--data-root=DIR]');
  }
  const healthRows = await Promise.all(ports.map(async (port) => {
    try { return { port, ok: await health(port) }; }
    catch (error) { return { port, ok: false, error: error.message }; }
  }));
  const memory = fs.readFileSync('/proc/meminfo', 'utf8');
  const mem = {};
  memory.split('\n').forEach((line) => {
    const match = line.match(/^([^:]+):\s+(\d+)\s+kB$/);
    if (match) mem[match[1]] = Number(match[2]) * 1024;
  });
  const load = fs.readFileSync('/proc/loadavg', 'utf8').trim().split(/\s+/);
  const fileNr = fs.readFileSync('/proc/sys/fs/file-nr', 'utf8').trim()
    .split(/\s+/).map(Number);
  const fileMax = Number(fs.readFileSync('/proc/sys/fs/file-max', 'utf8').trim());
  const stats = fs.statfsSync(dataRoot);
  const total = Number(stats.bsize) * Number(stats.blocks);
  const free = Number(stats.bsize) * Number(stats.bavail);
  const result = {
    version: 2,
    generatedAt: new Date().toISOString(),
    cell: {
      id: cellId,
      ok: healthRows.every((row) => row.ok),
      memoryUsedRatio: mem.MemTotal
        ? Math.max(0, 1 - mem.MemAvailable / mem.MemTotal) : 0,
      loadPerCore: os.cpus().length
        ? Number(load[0]) / os.cpus().length : 0,
      fdUtilization: fileMax ? (fileNr[0] || 0) / fileMax : 0,
      p99Ms: 0,
      diskUsedRatio: total ? Math.max(0, 1 - free / total) : 0,
      health: healthRows
    }
  };
  const out = arg('out', '');
  const text = JSON.stringify(result, null, 2) + '\n';
  if (out) {
    const target = path.resolve(out);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    const temporary = target + '.' + process.pid + '.tmp';
    fs.writeFileSync(temporary, text, 'utf8');
    fs.renameSync(temporary, target);
  } else {
    process.stdout.write(text);
  }
}

main().catch((error) => {
  process.stderr.write(String(error && error.stack || error) + '\n');
  process.exitCode = 1;
});
