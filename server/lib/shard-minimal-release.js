'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const {
  STABLE_SERVER_SHA256,
  patchServerSource
} = require('./shard-route-server-patch');

const SERVER_ROOT = path.resolve(__dirname, '..');
const ENTRY_FILES = [
  'lib/chat-route-plan.js',
  'lib/shard-runtime-manifest.js',
  'lib/shard-maintenance.js',
  'lib/single-cell-capacity-collector.js',
  'lib/shard-runtime-health.js',
  'lib/shard-physical-layout.js',
  'lib/shard-shadow-read.js',
  'lib/shard-release-readiness.js',
  'lib/shard-placement-rehearsal.js',
  'lib/shard-release-install.js',
  'lib/shard-owner-switch.js',
  'lib/shard-write-freeze.js',
  'lib/shard-user-directory.js',
  'tools/shard-maintenance-executor.js',
  'tools/single-cell-capacity-collect.js',
  'tools/single-cell-capacity-audit.js',
  'tools/shard-runtime-audit.js',
  'tools/shard-physical-layout-audit.js',
  'tools/shard-shadow-read-audit.js',
  'tools/shard-release-readiness.js',
  'tools/shard-placement-rehearsal.js',
  'tools/shard-release-install.js',
  'tools/shard-owner-switch.js',
  'tools/shard-write-freeze.js',
  'tools/shard-user-directory.js'
];
const ADDITIONAL_FILES = [
  'public/shard-maintenance.html',
  'shard-runtime-production.json',
  'shard-topologies.json',
  'run-shard-candidate.sh'
];

function sha256(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

function localDependencies(file) {
  const source = fs.readFileSync(file, 'utf8');
  const deps = [];
  const pattern = /require\(\s*['"](\.[^'"]+)['"]\s*\)/g;
  let match;
  while ((match = pattern.exec(source))) {
    const base = path.resolve(path.dirname(file), match[1]);
    for (const candidate of [base, base + '.js', path.join(base, 'index.js')]) {
      if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) {
        deps.push(candidate);
        break;
      }
    }
  }
  return deps;
}

function dependencyClosure(root, entries) {
  const queue = entries.map((relative) => path.resolve(root, relative));
  const files = new Set();
  while (queue.length) {
    const file = queue.shift();
    if (files.has(file)) continue;
    if (!fs.existsSync(file) || !fs.statSync(file).isFile()) {
      throw new Error('missing release dependency: ' + file);
    }
    files.add(file);
    for (const dep of localDependencies(file)) queue.push(dep);
  }
  return Array.from(files).sort();
}

function buildMinimalRelease(options) {
  const opts = options || {};
  const root = path.resolve(String(opts.serverRoot || SERVER_ROOT));
  const sourceFile = path.resolve(String(opts.serverSource || ''));
  const outDir = path.resolve(String(opts.outDir || ''));
  const expectedSha256 = String(opts.expectedSha256 || '').toLowerCase();
  if (!sourceFile || !outDir) throw new Error('serverSource and outDir are required');
  if (fs.existsSync(outDir)) throw new Error('outDir already exists');
  const source = fs.readFileSync(sourceFile);
  const patched = patchServerSource(source, {
    expectedSha256: expectedSha256 || undefined
  });
  const files = dependencyClosure(root, ENTRY_FILES);
  const additional = ADDITIONAL_FILES.map((relative) => path.resolve(root, relative));
  for (const file of additional) {
    if (!fs.existsSync(file) || !fs.statSync(file).isFile()) {
      throw new Error('missing release file: ' + file);
    }
  }
  const temporary = outDir + '.tmp-' + process.pid;
  if (fs.existsSync(temporary)) throw new Error('temporary output already exists');
  try {
    fs.mkdirSync(temporary, { recursive: true });
    fs.writeFileSync(path.join(temporary, 'server.js'), patched.source, 'utf8');
    const manifestFiles = [{
      path: 'server.js',
      kind: 'patched-server',
      sha256: sha256(Buffer.from(patched.source))
    }];
    for (const file of files.concat(additional)) {
      const relative = path.relative(root, file).replace(/\\/g, '/');
      const target = path.join(temporary, relative);
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.copyFileSync(file, target);
      if (relative.endsWith('.sh')) fs.chmodSync(target, 0o755);
      manifestFiles.push({
        path: relative,
        kind: relative.startsWith('tools/')
          ? 'tool'
          : relative.startsWith('public/') ? 'page'
            : relative.endsWith('.json') ? 'config'
              : relative.endsWith('.sh') ? 'launcher' : 'module',
        sha256: sha256(fs.readFileSync(file))
      });
    }
    const productionEligible = patched.sourceSha256 === STABLE_SERVER_SHA256;
    if (!productionEligible) {
      fs.writeFileSync(
        path.join(temporary, 'NONPRODUCTION.txt'),
        'NON-PRODUCTION PREVIEW\n\n'
          + 'The source server.js does not match the approved production stable SHA256.\n'
          + 'This package is for local verification only and must not be deployed.\n',
        'utf8'
      );
    }
    manifestFiles.sort((left, right) => left.path.localeCompare(right.path));
    const manifest = {
      version: 1,
      createdAt: new Date().toISOString(),
      sourceFile,
      sourceSha256: patched.sourceSha256,
      expectedSourceSha256: patched.expectedSha256,
      approvedProductionSourceSha256: STABLE_SERVER_SHA256,
      productionEligible,
      serverSha256: patched.outputSha256,
      patchChanges: patched.changes,
      entryFiles: ENTRY_FILES,
      files: manifestFiles,
      fileCount: manifestFiles.length,
      contentHash: sha256(Buffer.from(JSON.stringify(manifestFiles)))
    };
    fs.writeFileSync(
      path.join(temporary, 'release-manifest.json'),
      JSON.stringify(manifest, null, 2),
      'utf8'
    );
    fs.renameSync(temporary, outDir);
    return manifest;
  } catch (error) {
    try { fs.rmSync(temporary, { recursive: true, force: true }); } catch (_) { /* ignore */ }
    throw error;
  }
}

module.exports = {
  ENTRY_FILES,
  ADDITIONAL_FILES,
  localDependencies,
  dependencyClosure,
  buildMinimalRelease
};
