#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { ShardAuthorityStore } = require('../lib/shard-authority-store');
const {
  loadShardSnapshot,
  importShardSnapshot
} = require('../lib/shard-authority-migration');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function main() {
  const dataDir = path.resolve(String(arg('data', '') || ''));
  const secretFile = path.resolve(String(arg('secret', '') || ''));
  const databaseFile = path.resolve(String(arg('database', '') || ''));
  const shardId = Number(arg('shard-id'));
  const topologyId = String(arg('topology-id', '') || '');
  const writerEpoch = Number(arg('writer-epoch', '1'));
  const out = path.resolve(String(arg('out', '') || ''));
  if (!dataDir || !secretFile || !databaseFile || !topologyId || !out) {
    throw new Error('usage: import-shard-authority.js --data DIR --secret FILE '
      + '--database FILE --shard-id N --topology-id ID --out REPORT '
      + '[--writer-epoch N] [--all-chats]');
  }
  const snapshot = loadShardSnapshot({
    dataDir,
    secretFile,
    directOnly: !process.argv.includes('--all-chats')
  });
  const store = new ShardAuthorityStore({
    shardId,
    topologyId,
    databaseFile,
    writerEpoch
  });
  try {
    const report = Object.assign({
      version: 1,
      generatedAt: new Date().toISOString(),
      shardId,
      topologyId,
      databaseFile,
      dataDir,
      skipped: snapshot.skipped
    }, importShardSnapshot(store, snapshot));
    fs.mkdirSync(path.dirname(out), { recursive: true });
    fs.writeFileSync(out + '.tmp', JSON.stringify(report, null, 2), 'utf8');
    fs.renameSync(out + '.tmp', out);
    console.log(JSON.stringify(report, null, 2));
    if (!report.ok) process.exitCode = 2;
  } finally {
    store.close();
  }
}

try {
  main();
} catch (error) {
  console.error(error.stack || error);
  process.exitCode = 1;
}
