#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { openMessage } = require('../lib/shard-data-inventory');
const { SecurityVault } = require('../lib/security-vault');
const { hash } = require('../lib/shard-snapshot');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function argAll(name) {
  const values = [];
  process.argv.forEach((value, index) => {
    if (value === '--' + name && process.argv[index + 1]) values.push(process.argv[index + 1]);
  });
  return values;
}

function walk(root, names, found) {
  let entries = [];
  try { entries = fs.readdirSync(root, { withFileTypes: true }); }
  catch (_) { return; }
  for (const entry of entries) {
    const full = path.join(root, entry.name);
    if (entry.isDirectory()) {
      walk(full, names, found);
    } else if (entry.isFile() && names.has(entry.name)) {
      if (!found.has(entry.name)) found.set(entry.name, []);
      found.get(entry.name).push(full);
    }
  }
}

function main() {
  const dataDir = path.resolve(String(arg('data', '') || ''));
  const secretFile = path.resolve(String(arg('secret', '') || ''));
  const inventoryFile = path.resolve(String(arg('inventory', '') || ''));
  const out = path.resolve(String(arg('out', '') || ''));
  if (!dataDir || !secretFile || !inventoryFile || !out) {
    throw new Error('usage: upload-reference-repair-plan.js --data DIR --secret FILE '
      + '--inventory FILE --out FILE [--search-root DIR ...]');
  }
  const secret = fs.readFileSync(secretFile, 'utf8').trim();
  const inventory = JSON.parse(fs.readFileSync(inventoryFile, 'utf8'));
  const missing = Array.from(new Set((inventory.errors || [])
    .filter((row) => row.kind === 'upload-missing')
    .map((row) => path.basename(String(row.id || '')))
    .filter(Boolean))).sort();
  const missingSet = new Set(missing);
  const references = [];
  let vault = null;
  if (fs.existsSync(path.join(dataDir, 'keyring.json'))) {
    vault = new SecurityVault({ dataDir, rootMaterial: secret });
  }
  const messagesDir = path.join(dataDir, 'messages');
  const files = fs.existsSync(messagesDir)
    ? fs.readdirSync(messagesDir).filter((name) => name.endsWith('.jsonl')).sort()
    : [];
  for (const name of files) {
    const chatId = name.slice(0, -'.jsonl'.length);
    const lines = fs.readFileSync(path.join(messagesDir, name), 'utf8')
      .split('\n').filter((line) => line.trim());
    for (let index = 0; index < lines.length; index += 1) {
      let message;
      try { message = openMessage(secret, chatId, lines[index], vault); }
      catch (_) { continue; }
      const content = String(message && message.content || '');
      const matches = content.match(/\/uploads\/[A-Za-z0-9._-]+/g) || [];
      for (const imagePath of matches) {
        const basename = path.basename(imagePath);
        if (!missingSet.has(basename)) continue;
        references.push({
          chatId,
          messageId: message.id || '',
          kind: message.kind || '',
          senderId: message.senderId || '',
          createdAt: message.createdAt || '',
          path: imagePath,
          basename
        });
      }
    }
  }
  const found = new Map();
  const roots = argAll('search-root').map((root) => path.resolve(root));
  roots.forEach((root) => walk(root, missingSet, found));
  const items = missing.map((basename) => {
    const matches = found.get(basename) || [];
    return {
      basename,
      action: matches.length ? 'restore' : 'quarantine',
      sourceFiles: matches,
      references: references.filter((row) => row.basename === basename)
    };
  });
  const referenced = new Set(references.map((row) => row.basename));
  for (const basename of missing) {
    if (!referenced.has(basename)) {
      items.find((row) => row.basename === basename).references = [];
    }
  }
  const report = {
    version: 1,
    ok: true,
    generatedAt: new Date().toISOString(),
    dataDir,
    missing: missing.length,
    references: references.length,
    recoverable: items.filter((row) => row.action === 'restore').length,
    quarantine: items.filter((row) => row.action === 'quarantine').length,
    unresolvedReferences: items
      .filter((row) => row.action === 'quarantine')
      .reduce((sum, row) => sum + row.references.length, 0),
    searchRoots: roots,
    planHash: hash(items),
    items
  };
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out + '.tmp', JSON.stringify(report, null, 2), 'utf8');
  fs.renameSync(out + '.tmp', out);
  console.log(JSON.stringify({
    ok: report.ok,
    missing: report.missing,
    references: report.references,
    recoverable: report.recoverable,
    quarantine: report.quarantine,
    unresolvedReferences: report.unresolvedReferences,
    planHash: report.planHash,
    out
  }, null, 2));
}

if (require.main === module) {
  try { main(); }
  catch (error) {
    console.error(error.stack || error);
    process.exitCode = 1;
  }
}

module.exports = { main };
