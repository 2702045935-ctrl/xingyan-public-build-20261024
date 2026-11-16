#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { buildPlacementPlan } = require('../lib/shard-placement-plan');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function readJson(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch (_) { return fallback; }
}

function rows(value, key) {
  if (Array.isArray(value)) return value;
  return value && Array.isArray(value[key]) ? value[key] : [];
}

function main() {
  const dataDir = path.resolve(String(arg('data', '') || ''));
  const routePlanFile = path.resolve(String(arg('route-plan', '') || ''));
  const out = path.resolve(String(arg('out', '') || ''));
  if (!dataDir || !routePlanFile || !out) {
    throw new Error('usage: shard-placement-plan.js --data DIR '
      + '--route-plan FILE --out FILE');
  }
  const reads = readJson(path.join(dataDir, 'reads.json'), { reads: {} });
  const friendMeta = readJson(path.join(dataDir, 'friendmeta.json'), { byOwner: {} });
  const notices = readJson(path.join(dataDir, 'moment-notices.json'), { items: [] });
  const messagesDir = path.join(dataDir, 'messages');
  const messageThreads = fs.existsSync(messagesDir)
    ? fs.readdirSync(messagesDir).filter((name) => name.endsWith('.jsonl'))
      .map((name) => name.slice(0, -'.jsonl'.length)).sort()
    : [];
  const plan = buildPlacementPlan({
    routePlan: readJson(routePlanFile, {}),
    data: {
      users: rows(readJson(path.join(dataDir, 'users.json'), { users: [] }), 'users'),
      friendships: rows(readJson(path.join(dataDir, 'friendships.json'), { friendships: [] }), 'friendships'),
      chats: rows(readJson(path.join(dataDir, 'chats.json'), { chats: [] }), 'chats'),
      reads: reads.reads || {},
      friendMeta: friendMeta.byOwner || {},
      moments: rows(readJson(path.join(dataDir, 'moments.json'), { moments: [] }), 'moments'),
      momentNotices: notices.items || [],
      messageThreads
    }
  });
  fs.mkdirSync(path.dirname(out), { recursive: true });
  const temporary = out + '.' + process.pid + '.tmp';
  fs.writeFileSync(temporary, JSON.stringify(plan, null, 2), 'utf8');
  fs.renameSync(temporary, out);
  console.log(JSON.stringify({
    ok: plan.ok,
    hash: plan.hash,
    itemCount: plan.itemCount,
    byType: plan.byType,
    byShard: plan.byShard.map((row) => row.total),
    failures: plan.failures.length,
    out
  }, null, 2));
  if (!plan.ok) process.exitCode = 2;
}

if (require.main === module) {
  try { main(); }
  catch (error) {
    console.error(error.stack || error);
    process.exitCode = 1;
  }
}

module.exports = { main };
