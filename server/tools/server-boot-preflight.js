'use strict';

const fs = require('fs');
const path = require('path');
const { resolveTopology } = require('../lib/shard-topology');

const ROOT = path.resolve(__dirname, '..');
const ENTRY = path.join(ROOT, 'server.js');
const missing = [];
const visited = new Set();
const OPTIONAL_LOCAL_MODULES = new Set(['./turn.js']);

function resolveLocalModule(fromFile, request) {
  const base = path.resolve(path.dirname(fromFile), request);
  const candidates = [
    base,
    base + '.js',
    base + '.json',
    path.join(base, 'index.js')
  ];
  return candidates.find((candidate) => {
    try {
      return fs.statSync(candidate).isFile();
    } catch (_) {
      return false;
    }
  }) || '';
}

function inspect(file) {
  const resolved = path.resolve(file);
  if (visited.has(resolved)) return;
  visited.add(resolved);
  const source = fs.readFileSync(resolved, 'utf8');
  const pattern = /require\(\s*['"](\.[^'"]+)['"]\s*\)/g;
  let match;
  while ((match = pattern.exec(source))) {
    const target = resolveLocalModule(resolved, match[1]);
    if (!target) {
      if (OPTIONAL_LOCAL_MODULES.has(match[1])) continue;
      missing.push({
        from: path.relative(ROOT, resolved).replace(/\\/g, '/'),
        request: match[1]
      });
      continue;
    }
    if (target.endsWith('.js')) inspect(target);
  }
}

inspect(ENTRY);

const topologyFile = path.join(ROOT, 'shard-topologies.json');
const registry = JSON.parse(fs.readFileSync(topologyFile, 'utf8'));
for (const topologyId of Object.keys(registry.topologies || {})) {
  resolveTopology(topologyFile, topologyId);
}

if (missing.length) {
  console.error(JSON.stringify({ ok: false, missing }, null, 2));
  process.exitCode = 1;
} else {
  console.log(JSON.stringify({
    ok: true,
    entry: path.relative(ROOT, ENTRY).replace(/\\/g, '/'),
    localModules: visited.size,
    topologies: Object.keys(registry.topologies || {})
  }, null, 2));
}
