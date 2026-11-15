#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { auditMessageShardSet } = require('../lib/message-consistency-audit-matrix');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

async function main() {
  const configFile = arg('config');
  if (!configFile) {
    throw new Error('usage: message-consistency-audit-matrix.js --config FILE '
      + '[--expected-messages N] [--require-client-id] [--max-issues N] [--out FILE]');
  }
  const absoluteConfig = path.resolve(configFile);
  const config = JSON.parse(fs.readFileSync(absoluteConfig, 'utf8'));
  const offlineRoot = arg('offline-root', config.offlineRoot);
  if (!offlineRoot) {
    throw new Error('offlineRoot is required; point it at the isolated shard copy root');
  }
  const expectedArg = arg('expected-messages');
  const report = await auditMessageShardSet({
    baseDir: path.dirname(absoluteConfig),
    offlineRoot,
    shards: config.shards,
    expectedMessages: expectedArg !== undefined
      ? Number(expectedArg)
      : config.expectedMessages,
    requireClientId: process.argv.includes('--require-client-id')
      || config.requireClientId === true,
    maxIssues: Number(arg('max-issues', config.maxIssues || '20000'))
  });
  const text = JSON.stringify(report, null, 2);
  const out = arg('out');
  if (out) {
    const file = path.resolve(out);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const temporary = file + '.' + process.pid + '.tmp';
    fs.writeFileSync(temporary, text, 'utf8');
    fs.renameSync(temporary, file);
    console.log(JSON.stringify({
      ok: report.ok,
      shardCount: report.shardCount,
      messageCount: report.messageCount,
      expectedMessages: report.expectedMessages,
      issues: report.issueCount,
      errors: report.errorCount,
      warnings: report.warningCount,
      fingerprint: report.fingerprint,
      out: file
    }, null, 2));
  } else {
    process.stdout.write(text);
  }
  if (!report.ok) process.exitCode = 2;
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.stack || error);
    process.exitCode = 1;
  });
}

module.exports = { main };
