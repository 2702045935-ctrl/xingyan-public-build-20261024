'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

function runSingleCellCapacityCollector(options) {
  const opts = options || {};
  const tool = path.resolve(String(opts.tool || ''));
  const manifest = path.resolve(String(opts.manifest || ''));
  const dataDir = path.resolve(String(opts.dataDir || ''));
  const out = path.resolve(String(opts.out || ''));
  const timeoutMs = Math.max(1000, Number(opts.timeoutMs) || 15000);
  if (!tool || !manifest || !dataDir || !out) {
    throw new Error('tool, manifest, dataDir and out are required');
  }
  const spawnImpl = opts.spawnImpl || spawn;
  return new Promise((resolve, reject) => {
    const child = spawnImpl(process.execPath, [
      tool,
      '--manifest=' + manifest,
      '--data-dir=' + dataDir,
      '--out=' + out
    ], {
      cwd: path.dirname(tool),
      env: Object.assign({}, process.env),
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });
    let stdout = '';
    let stderr = '';
    const timer = setTimeout(() => {
      try { child.kill(); } catch (_) { /* ignore */ }
    }, timeoutMs);
    child.stdout.on('data', (chunk) => { stdout += chunk.toString(); });
    child.stderr.on('data', (chunk) => { stderr += chunk.toString(); });
    child.once('error', (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.once('exit', (code) => {
      clearTimeout(timer);
      let report = null;
      try {
        report = JSON.parse(fs.readFileSync(out, 'utf8'));
      } catch (error) {
        reject(new Error('capacity collector produced no valid report: ' + error.message
          + (stderr ? ' / ' + stderr.slice(0, 1000) : '')));
        return;
      } finally {
        try { fs.rmSync(out, { force: true }); } catch (_) { /* ignore */ }
      }
      resolve({
        code,
        stdout: stdout.slice(0, 4000),
        stderr: stderr.slice(0, 4000),
        report
      });
    });
  });
}

module.exports = {
  runSingleCellCapacityCollector
};
