'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { STABLE_SERVER_SHA256 } = require('./shard-route-server-patch');

function sha256(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function safeRelative(value) {
  const relative = String(value || '').replace(/\\/g, '/');
  if (!relative || relative.startsWith('/') || relative.split('/').includes('..')) {
    throw new Error('unsafe release path: ' + relative);
  }
  return relative;
}

function verifyReleaseManifest(overlayDir) {
  const manifestFile = path.join(overlayDir, 'release-manifest.json');
  const manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf8'));
  if (Number(manifest.version) !== 1 || !Array.isArray(manifest.files)) {
    throw new Error('release manifest is invalid');
  }
  const seen = new Set();
  for (const row of manifest.files) {
    const relative = safeRelative(row.path);
    if (seen.has(relative)) throw new Error('duplicate release path: ' + relative);
    seen.add(relative);
    const file = path.join(overlayDir, relative);
    if (!fs.existsSync(file) || !fs.statSync(file).isFile()) {
      throw new Error('release file missing: ' + relative);
    }
    if (!/^[a-f0-9]{64}$/i.test(String(row.sha256 || ''))
        || sha256(file) !== String(row.sha256).toLowerCase()) {
      throw new Error('release file hash mismatch: ' + relative);
    }
  }
  if (!seen.has('server.js')) throw new Error('release has no server.js');
  return manifest;
}

function installShardRelease(options) {
  const opts = options || {};
  const overlayDir = path.resolve(String(opts.overlayDir || ''));
  const baseAppDir = path.resolve(String(opts.baseAppDir || ''));
  const outDir = path.resolve(String(opts.outDir || ''));
  if (!overlayDir || !baseAppDir || !outDir) {
    throw new Error('overlayDir, baseAppDir and outDir are required');
  }
  if (outDir === overlayDir || outDir === baseAppDir) {
    throw new Error('outDir must differ from inputs');
  }
  if (outDir.startsWith(overlayDir + path.sep)
      || outDir.startsWith(baseAppDir + path.sep)
      || overlayDir.startsWith(outDir + path.sep)
      || baseAppDir.startsWith(outDir + path.sep)) {
    throw new Error('output path overlaps an input');
  }
  if (fs.existsSync(outDir)) throw new Error('outDir already exists');
  const baseServer = path.join(baseAppDir, 'server.js');
  if (!fs.existsSync(baseServer)) throw new Error('base app has no server.js');
  const baseServerSha256 = sha256(baseServer);
  const expected = String(opts.expectedBaseSha256 || STABLE_SERVER_SHA256).toLowerCase();
  if (baseServerSha256 !== expected) {
    throw new Error('base server hash mismatch: expected=' + expected
      + ' actual=' + baseServerSha256);
  }
  const manifest = verifyReleaseManifest(overlayDir);
  if (manifest.productionEligible !== true) {
    throw new Error('release is marked non-production');
  }
  if (manifest.sourceSha256 !== expected) {
    throw new Error('release was not built from this approved base');
  }

  const temporary = outDir + '.tmp-' + process.pid;
  if (fs.existsSync(temporary)) throw new Error('temporary output already exists');
  try {
    fs.cpSync(baseAppDir, temporary, {
      recursive: true,
      force: true,
      errorOnExist: true
    });
    for (const row of manifest.files) {
      const relative = safeRelative(row.path);
      const source = path.join(overlayDir, relative);
      const target = path.join(temporary, relative);
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.copyFileSync(source, target);
      if (row.kind === 'launcher' || relative.endsWith('.sh')) {
        fs.chmodSync(target, 0o755);
      }
    }
    const finalServerSha256 = sha256(path.join(temporary, 'server.js'));
    if (finalServerSha256 !== String(manifest.serverSha256).toLowerCase()) {
      throw new Error('installed server hash mismatch');
    }
    const report = {
      version: 1,
      ok: true,
      baseAppDir,
      overlayDir,
      outDir,
      baseServerSha256,
      finalServerSha256,
      releaseContentHash: manifest.contentHash,
      installedFiles: manifest.files.map((row) => ({
        path: row.path,
        sha256: row.sha256
      })),
      createdAt: new Date().toISOString()
    };
    fs.writeFileSync(
      path.join(temporary, 'staged-install-report.json'),
      JSON.stringify(report, null, 2),
      'utf8'
    );
    fs.renameSync(temporary, outDir);
    return report;
  } catch (error) {
    try { fs.rmSync(temporary, { recursive: true, force: true }); } catch (_) { /* ignore */ }
    throw error;
  }
}

module.exports = {
  verifyReleaseManifest,
  installShardRelease
};
