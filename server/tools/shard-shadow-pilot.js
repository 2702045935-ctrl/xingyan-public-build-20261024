#!/usr/bin/env node
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { createShardShadowService } = require('../lib/shard-shadow-service');
const { buildRoutePlan } = require('../lib/shard-route-plan');
const { loadManifest } = require('../lib/shard-runtime-manifest');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function readJson(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (_) {
    return fallback;
  }
}

function rowsOf(value, key) {
  if (Array.isArray(value)) return value;
  return value && Array.isArray(value[key]) ? value[key] : [];
}

function duplicateIds(rows, idOf) {
  const seen = new Set();
  const duplicates = [];
  for (const row of rows || []) {
    const id = String(idOf(row) || '');
    if (!id) continue;
    if (seen.has(id)) duplicates.push(id);
    seen.add(id);
  }
  return Array.from(new Set(duplicates));
}

function entityOwnerViolations(cluster) {
  const seen = new Map();
  const violations = [];
  for (const [shard, log] of cluster.logs.entries()) {
    for (const [entityKey, state] of log.entities.entries()) {
      if (seen.has(entityKey) && seen.get(entityKey) !== shard) {
        violations.push({
          entity: entityKey,
          firstShard: seen.get(entityKey),
          secondShard: shard,
          version: state.version
        });
      } else {
        seen.set(entityKey, shard);
      }
    }
  }
  return violations;
}

function distribution(cluster, kind, rows, idOf) {
  const counts = Array.from({ length: cluster.shardCount }, () => 0);
  const invalid = [];
  for (const row of rows || []) {
    const id = String(idOf(row) || '');
    if (!id) {
      invalid.push('');
      continue;
    }
    const shard = cluster.ownerShard(kind, id);
    if (!Number.isInteger(shard) || shard < 0 || shard >= cluster.shardCount) {
      invalid.push(id);
      continue;
    }
    counts[shard] += 1;
  }
  return { counts, invalid };
}

function runShadowPilot(options) {
  const opts = options || {};
  const sourceDir = path.resolve(String(opts.sourceDir || ''));
  if (!sourceDir) throw new Error('sourceDir is required');
  const workDir = path.resolve(String(opts.workDir
    || path.join(os.tmpdir(), 'xingyan-shadow-pilot-' + process.pid)));
  const relative = path.relative(sourceDir, workDir);
  if (!relative || (!relative.startsWith('..') && !path.isAbsolute(relative))) {
    throw new Error('shadow workDir must be outside the source data directory');
  }
  const manifestResult = loadManifest(opts.manifestFile, {
    topologyFile: opts.topologyFile
  });
  if (!manifestResult.ok) {
    throw new Error('runtime manifest is invalid: '
      + JSON.stringify(manifestResult.failures));
  }
  const users = rowsOf(readJson(path.join(sourceDir, 'users.json'), { users: [] }), 'users');
  const friendships = rowsOf(
    readJson(path.join(sourceDir, 'friendships.json'), { friendships: [] }),
    'friendships'
  );
  const chats = rowsOf(readJson(path.join(sourceDir, 'chats.json'), { chats: [] }), 'chats');
  const readsStore = readJson(path.join(sourceDir, 'reads.json'), { reads: {}, cleared: {} });
  const friendMetaStore = readJson(path.join(sourceDir, 'friendmeta.json'), { byOwner: {} });
  const moments = rowsOf(readJson(path.join(sourceDir, 'moments.json'), { moments: [] }), 'moments');
  const noticeStore = readJson(path.join(sourceDir, 'moment-notices.json'), {
    items: [],
    seen: {}
  });
  const legacy = {
    users,
    friendships,
    chats,
    reads: readsStore.reads || {},
    cleared: readsStore.cleared || {},
    friendMeta: friendMetaStore.byOwner || {},
    moments,
    momentNotices: noticeStore.items || [],
    momentNoticeSeen: noticeStore.seen || {},
    transfers: [],
    redpackets: [],
    messages: {}
  };
  let sequence = 0;
  const service = createShardShadowService({
    enabled: '1',
    dataDir: workDir,
    shardCount: manifestResult.manifest.shardCount,
    topologyId: manifestResult.manifest.topologyId,
    ownerId: 'shadow-pilot:' + process.pid,
    snapshotStores: true,
    uid: (prefix) => prefix + '-shadow-' + (++sequence),
    now: () => new Date().toISOString(),
    legacy
  });
  try {
    const audit = service.audit(legacy);
    const clusterAudit = service.cluster.verify();
    const duplicateOwners = entityOwnerViolations(service.cluster);
    const userDistribution = distribution(service.cluster, 'user', users, (row) => row.id);
    const chatDistribution = distribution(service.cluster, 'chat', chats, (row) => row.id);
    const sourceDuplicates = {
      users: duplicateIds(users, (row) => row.id),
      friendships: duplicateIds(friendships, (row) => row.id),
      chats: duplicateIds(chats, (row) => row.id),
      moments: duplicateIds(moments, (row) => row.id)
    };
    const routePlan = buildRoutePlan({
      users,
      chats,
      shardCount: manifestResult.manifest.shardCount,
      ports: manifestResult.manifest.shards.map((row) => row.backendPort),
      topologyId: manifestResult.manifest.topologyId,
      baselineDate: manifestResult.manifest.frozenDate,
      createdAt: new Date().toISOString()
    });
    const failures = [];
    if (!audit.ok) failures.push('shadow-audit-diff');
    if (!clusterAudit.ok) failures.push('cluster-integrity');
    if (duplicateOwners.length) failures.push('duplicate-owner');
    if (userDistribution.invalid.length) failures.push('invalid-user-owner');
    if (chatDistribution.invalid.length) failures.push('invalid-chat-owner');
    if (sourceDuplicates.users.length) failures.push('duplicate-user-id');
    if (sourceDuplicates.friendships.length) failures.push('duplicate-friendship-id');
    if (sourceDuplicates.chats.length) failures.push('duplicate-chat-id');
    if (sourceDuplicates.moments.length) failures.push('duplicate-moment-id');
    return {
      ok: failures.length === 0,
      failures,
      sourceDir,
      workDir,
      topologyId: manifestResult.manifest.topologyId,
      manifestHash: manifestResult.hash,
      sourceCounts: {
        users: users.length,
        friendships: friendships.length,
        chats: chats.length,
        reads: Object.values(legacy.reads).reduce(
          (sum, row) => sum + Object.keys(row || {}).length,
          0
        ),
        moments: moments.length
      },
      sourceDuplicates,
      migration: service.migration,
      audit: {
        ok: audit.ok,
        checked: audit.checked,
        diffCount: audit.diffs.length,
        diffs: audit.diffs.slice(0, 200)
      },
      clusterAudit,
      duplicateOwners,
      owners: {
        users: userDistribution.counts,
        chats: chatDistribution.counts
      },
      routePlanHash: routePlan.hash,
      reportFile: service.reportFile,
      close() {
        service.close();
      }
    };
  } catch (error) {
    service.close();
    throw error;
  }
}

function main() {
  const root = path.resolve(__dirname, '..');
  const sourceDir = arg('data');
  const out = arg('out');
  if (!sourceDir) {
    throw new Error('usage: shard-shadow-pilot.js --data DIR --out FILE '
      + '[--work DIR] [--manifest FILE] [--topology FILE]');
  }
  const result = runShadowPilot({
    sourceDir,
    workDir: arg('work'),
    manifestFile: path.resolve(arg('manifest', path.join(root, 'shard-runtime-production.json'))),
    topologyFile: path.resolve(arg('topology', path.join(root, 'shard-topologies.json')))
  });
  const close = result.close;
  delete result.close;
  const text = JSON.stringify(result, null, 2);
  if (out) {
    const file = path.resolve(out);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const temporary = file + '.' + process.pid + '.tmp';
    fs.writeFileSync(temporary, text, 'utf8');
    fs.renameSync(temporary, file);
  }
  process.stdout.write(text + '\n');
  close();
  if (!result.ok) process.exitCode = 2;
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    console.error(error.stack || error);
    process.exitCode = 1;
  }
}

module.exports = { runShadowPilot };
