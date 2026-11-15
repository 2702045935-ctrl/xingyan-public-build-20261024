'use strict';

const fs = require('fs');
const path = require('path');
const { auditMessageConsistency } = require('./message-consistency-audit');
const { hash } = require('./shard-snapshot');

function stableText(value) {
  return String(value == null ? '' : value);
}

function textCompare(left, right) {
  const a = stableText(left);
  const b = stableText(right);
  return a < b ? -1 : (a > b ? 1 : 0);
}

function sortIssues(left, right) {
  return textCompare(left.sourceId, right.sourceId)
    || textCompare(left.kind, right.kind)
    || textCompare(left.chatId, right.chatId)
    || textCompare(left.messageId, right.messageId)
    || Number(left.seq || 0) - Number(right.seq || 0);
}

function isWithin(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === ''
    || (!relative.startsWith('..' + path.sep)
      && relative !== '..'
      && !path.isAbsolute(relative));
}

function normalizeShards(value, baseDir, offlineRoot) {
  const rows = Array.isArray(value) ? value : [];
  const sourceIds = new Set();
  const dataDirs = new Set();
  const root = offlineRoot ? path.resolve(baseDir, offlineRoot) : '';
  if (root && (!fs.existsSync(root) || !fs.statSync(root).isDirectory())) {
    throw new Error('offlineRoot does not exist: ' + root);
  }
  return rows.map((input, index) => {
    const row = input || {};
    const sourceId = stableText(row.sourceId).trim();
    if (!sourceId) throw new Error('shard ' + index + ' has no sourceId');
    if (sourceIds.has(sourceId)) throw new Error('duplicate shard sourceId: ' + sourceId);
    sourceIds.add(sourceId);
    const dataDir = path.resolve(baseDir, stableText(row.dataDir));
    if (!row.dataDir || !fs.existsSync(dataDir) || !fs.statSync(dataDir).isDirectory()) {
      throw new Error('shard ' + sourceId + ' dataDir does not exist');
    }
    if (dataDirs.has(dataDir)) throw new Error('duplicate shard dataDir: ' + dataDir);
    dataDirs.add(dataDir);
    const databaseFile = row.databaseFile
      ? path.resolve(baseDir, stableText(row.databaseFile))
      : '';
    if (root && (!isWithin(root, dataDir) || (databaseFile && !isWithin(root, databaseFile)))) {
      throw new Error('shard ' + sourceId + ' is outside offlineRoot');
    }
    const secretFile = row.secretFile
      ? path.resolve(baseDir, stableText(row.secretFile))
      : '';
    return {
      sourceId,
      dataDir,
      databaseFile,
      secret: secretFile ? fs.readFileSync(secretFile, 'utf8').trim() : ''
    };
  });
}

async function auditMessageShardSet(options) {
  const opts = options || {};
  const baseDir = path.resolve(stableText(opts.baseDir || '.'));
  const shards = normalizeShards(opts.shards, baseDir, opts.offlineRoot);
  if (!shards.length) throw new Error('at least one shard is required');
  const sharedIndex = {
    messagesById: new Map(),
    clientOwners: new Map(),
    chatOwners: new Map()
  };
  const reports = [];
  for (const shard of shards) {
    reports.push(await auditMessageConsistency({
      dataDir: shard.dataDir,
      databaseFile: shard.databaseFile,
      secret: shard.secret,
      sourceId: shard.sourceId,
      maxIssues: opts.maxIssues,
      requireClientId: opts.requireClientId === true,
      sharedIndex
    }));
  }

  const issues = reports.flatMap((report) =>
    report.issues.map((issue) => Object.assign({}, issue, {
      sourceId: report.sourceId
    }))
  ).sort(sortIssues);
  const messageCount = reports.reduce((sum, report) =>
    sum + (Number(report.counts && report.counts.messages) || 0), 0);
  const hasExpectedMessages = opts.expectedMessages !== undefined
    && opts.expectedMessages !== null
    && opts.expectedMessages !== '';
  const expectedMessages = hasExpectedMessages ? Number(opts.expectedMessages) : NaN;
  const countMatches = !hasExpectedMessages
    || (Number.isInteger(expectedMessages)
      && expectedMessages >= 0
      && messageCount === expectedMessages);
  const shardSummaries = reports.map((report) => ({
    sourceId: report.sourceId,
    fingerprint: report.fingerprint,
    ok: report.ok,
    messageFiles: Number(report.counts && report.counts.messageFiles) || 0,
    messages: Number(report.counts && report.counts.messages) || 0,
    reliabilityMessages: Number(report.counts && report.counts.reliabilityMessages) || 0,
    errorCount: Number(report.errorCount) || 0,
    warningCount: Number(report.warningCount) || 0,
    suppressedIssues: Number(report.suppressedIssues) || 0
  })).sort((left, right) => textCompare(left.sourceId, right.sourceId));

  const deterministic = {
    version: 1,
    audit: 'message-consistency-shard-set',
    shardCount: shardSummaries.length,
    messageCount,
    expectedMessages: hasExpectedMessages ? expectedMessages : null,
    countMatches,
    shards: shardSummaries,
    issues,
    issueCount: issues.length,
    errorCount: reports.reduce((sum, report) => sum + (Number(report.errorCount) || 0), 0),
    warningCount: reports.reduce((sum, report) => sum + (Number(report.warningCount) || 0), 0),
    suppressedIssues: reports.reduce((sum, report) =>
      sum + (Number(report.suppressedIssues) || 0), 0)
  };
  const fingerprint = hash(deterministic);
  return Object.assign({
    generatedAt: new Date().toISOString(),
    readOnly: true,
    ok: countMatches
      && deterministic.suppressedIssues === 0
      && reports.every((report) => report.readOnly === true && report.ok === true)
  }, deterministic, { fingerprint });
}

module.exports = {
  auditMessageShardSet,
  isWithin,
  normalizeShards
};
