#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { loadShardSnapshot } = require('../lib/shard-authority-migration');
const { auditShardAuthority } = require('../lib/shard-authority-shadow-audit');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function main() {
  const dataDir = path.resolve(String(arg('data', '') || ''));
  const secretFile = path.resolve(String(arg('secret', '') || ''));
  const databaseFile = path.resolve(String(arg('database', '') || ''));
  const out = path.resolve(String(arg('out', '') || ''));
  if (!dataDir || !secretFile || !databaseFile || !out) {
    throw new Error('usage: audit-shard-authority.js --data DIR --secret FILE '
      + '--database FILE --out REPORT [--all-chats]');
  }
  const snapshot = loadShardSnapshot({
    dataDir,
    secretFile,
    directOnly: !process.argv.includes('--all-chats')
  });
  const report = auditShardAuthority({ databaseFile, snapshot });
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out + '.tmp', JSON.stringify(report, null, 2), 'utf8');
  fs.renameSync(out + '.tmp', out);
  console.log(JSON.stringify({
    ok: report.ok,
    chats: report.chats,
    messages: report.messages,
    issues: report.issues.length,
    out
  }, null, 2));
  if (!report.ok) process.exitCode = 2;
}

try {
  main();
} catch (error) {
  console.error(error.stack || error);
  process.exitCode = 1;
}
