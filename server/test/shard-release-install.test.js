'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const { buildMinimalRelease } = require('../lib/shard-minimal-release');
const { installShardRelease } = require('../lib/shard-release-install');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-release-install-'));
try {
  const stable = execFileSync('git', ['show', 'bc09897:server/server.js'], {
    cwd: path.resolve(__dirname, '..', '..'),
    maxBuffer: 8 * 1024 * 1024
  });
  const baseApp = path.join(root, 'base-app');
  fs.mkdirSync(baseApp);
  fs.writeFileSync(path.join(baseApp, 'server.js'), stable);
  fs.writeFileSync(path.join(baseApp, 'stable-only.txt'), 'keep');
  const sourceFile = path.join(root, 'stable-server.js');
  fs.writeFileSync(sourceFile, stable);
  const release = path.join(root, 'release');
  const releaseManifest = buildMinimalRelease({
    serverSource: sourceFile,
    outDir: release,
    expectedSha256: crypto.createHash('sha256').update(stable).digest('hex')
  });
  assert.strictEqual(releaseManifest.productionEligible, false);
  assert.throws(() => installShardRelease({
    overlayDir: release,
    baseAppDir: baseApp,
    outDir: path.join(root, 'nonprod-install'),
    expectedBaseSha256: reportBaseHash(stable)
  }), /non-production/);

  const manifestFile = path.join(release, 'release-manifest.json');
  releaseManifest.productionEligible = true;
  releaseManifest.sourceSha256 = crypto.createHash('sha256').update(stable).digest('hex');
  fs.writeFileSync(manifestFile, JSON.stringify(releaseManifest, null, 2));
  const outDir = path.join(root, 'installed');
  const report = installShardRelease({
    overlayDir: release,
    baseAppDir: baseApp,
    outDir,
    expectedBaseSha256: reportBaseHash(stable)
  });
  assert.strictEqual(report.finalServerSha256, releaseManifest.serverSha256);
  assert.strictEqual(fs.readFileSync(path.join(outDir, 'stable-only.txt'), 'utf8'), 'keep');
  assert.ok(fs.existsSync(path.join(outDir, 'staged-install-report.json')));
  assert.ok(fs.existsSync(path.join(outDir, 'public', 'shard-maintenance.html')));
  if (process.platform !== 'win32') {
    assert.notStrictEqual(
      fs.statSync(path.join(outDir, 'run-shard-candidate.sh')).mode & 0o111,
      0
    );
  }
  assert.throws(() => installShardRelease({
    overlayDir: release,
    baseAppDir: baseApp,
    outDir
  }), /already exists/);

  const badBase = path.join(root, 'bad-base');
  fs.mkdirSync(badBase);
  fs.writeFileSync(path.join(badBase, 'server.js'), 'bad');
  assert.throws(() => installShardRelease({
    overlayDir: release,
    baseAppDir: badBase,
    outDir: path.join(root, 'bad-installed')
  }), /base server hash mismatch/);

  console.log('shard-release-install: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}

function reportBaseHash(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}
