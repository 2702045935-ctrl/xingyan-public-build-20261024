#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { buildMinimalRelease } = require('../lib/shard-minimal-release');

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const row = process.argv.slice(2).find((value) => value.startsWith(prefix));
  return row ? row.slice(prefix.length) : fallback;
}

function main() {
  const serverSource = arg('server-source', '');
  const outDir = arg('out-dir', '');
  if (!serverSource || !outDir) {
    throw new Error('usage: shard-minimal-release.js --server-source=FILE '
      + '--out-dir=DIR [--expected-sha256=SHA256]');
  }
  const manifest = buildMinimalRelease({
    serverSource,
    outDir,
    expectedSha256: arg('expected-sha256', '')
  });
  console.log(JSON.stringify({
    ok: true,
    outDir: path.resolve(outDir),
    productionEligible: manifest.productionEligible,
    serverSha256: manifest.serverSha256,
    fileCount: manifest.fileCount,
    contentHash: manifest.contentHash
  }, null, 2));
}

try {
  main();
} catch (error) {
  console.error(error.stack || error);
  process.exitCode = 1;
}
