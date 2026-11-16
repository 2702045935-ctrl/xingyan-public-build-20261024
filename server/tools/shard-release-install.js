#!/usr/bin/env node
'use strict';

const path = require('path');
const { installShardRelease } = require('../lib/shard-release-install');

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const row = process.argv.slice(2).find((value) => value.startsWith(prefix));
  return row ? row.slice(prefix.length) : fallback;
}

function main() {
  const overlayDir = arg('overlay', '');
  const baseAppDir = arg('base-app', '');
  const outDir = arg('out-dir', '');
  if (!overlayDir || !baseAppDir || !outDir) {
    throw new Error('usage: shard-release-install.js --overlay=DIR '
      + '--base-app=DIR --out-dir=DIR [--expected-base-sha256=SHA256]');
  }
  const report = installShardRelease({
    overlayDir,
    baseAppDir,
    outDir,
    expectedBaseSha256: arg('expected-base-sha256', '')
  });
  console.log(JSON.stringify({
    ok: true,
    outDir: path.resolve(outDir),
    baseServerSha256: report.baseServerSha256,
    finalServerSha256: report.finalServerSha256,
    files: report.installedFiles.length
  }, null, 2));
}

try {
  main();
} catch (error) {
  console.error(error.stack || error);
  process.exitCode = 1;
}
