#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const {
  STABLE_SERVER_SHA256,
  patchServerSource
} = require('../lib/shard-route-server-patch');

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const row = process.argv.slice(2).find((value) => value.startsWith(prefix));
  return row ? row.slice(prefix.length) : fallback;
}

function main() {
  const sourceFile = path.resolve(arg('source', ''));
  const outFile = path.resolve(arg('out', ''));
  const reportFile = arg('report', '');
  if (!sourceFile || !outFile) {
    throw new Error('usage: shard-route-patch.js --source=FILE --out=FILE '
      + '[--expected-sha256=SHA256] [--report=FILE]');
  }
  if (sourceFile === outFile) throw new Error('output must differ from source');
  if (fs.existsSync(outFile)) throw new Error('output already exists');
  const source = fs.readFileSync(sourceFile);
  const result = patchServerSource(source, {
    expectedSha256: arg('expected-sha256', STABLE_SERVER_SHA256)
  });
  fs.mkdirSync(path.dirname(outFile), { recursive: true });
  fs.writeFileSync(outFile, result.source, 'utf8');
  const report = {
    version: 1,
    ok: true,
    sourceFile,
    outputFile: outFile,
    sourceSha256: result.sourceSha256,
    outputSha256: result.outputSha256,
    changes: result.changes,
    helperFiles: result.helperFiles
  };
  if (reportFile) {
    const file = path.resolve(reportFile);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, JSON.stringify(report, null, 2), 'utf8');
  }
  console.log(JSON.stringify(report, null, 2));
}

try {
  main();
} catch (error) {
  console.error(error.stack || error);
  process.exitCode = 1;
}
