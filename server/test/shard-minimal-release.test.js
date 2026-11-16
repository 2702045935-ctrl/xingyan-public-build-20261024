'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');
const { buildMinimalRelease } = require('../lib/shard-minimal-release');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-minimal-release-'));
try {
  const stable = execFileSync('git', ['show', 'bc09897:server/server.js'], {
    cwd: path.resolve(__dirname, '..', '..'),
    maxBuffer: 8 * 1024 * 1024
  });
  const sourceFile = path.join(root, 'stable-server.js');
  const outDir = path.join(root, 'release');
  fs.writeFileSync(sourceFile, stable);
  const expected = crypto.createHash('sha256').update(stable).digest('hex');
  const manifest = buildMinimalRelease({
    serverSource: sourceFile,
    outDir,
    expectedSha256: expected
  });
  assert.strictEqual(manifest.fileCount >= 10, true);
  assert.strictEqual(manifest.patchChanges.length, 12);
  assert.strictEqual(manifest.productionEligible, false);
  assert.ok(fs.existsSync(path.join(outDir, 'NONPRODUCTION.txt')));
  assert.ok(fs.existsSync(path.join(outDir, 'server.js')));
  assert.ok(fs.existsSync(path.join(outDir, 'lib', 'chat-route-plan.js')));
  assert.ok(fs.existsSync(path.join(outDir, 'lib', 'shard-maintenance.js')));
  assert.ok(fs.existsSync(path.join(outDir, 'tools', 'shard-maintenance-executor.js')));
  assert.ok(fs.existsSync(path.join(outDir, 'tools', 'shard-release-install.js')));
  assert.ok(fs.existsSync(path.join(outDir, 'public', 'shard-maintenance.html')));
  assert.ok(fs.existsSync(path.join(outDir, 'shard-runtime-production.json')));
  assert.ok(fs.existsSync(path.join(outDir, 'shard-topologies.json')));
  assert.ok(fs.existsSync(path.join(outDir, 'run-shard-candidate.sh')));
  assert.ok(fs.existsSync(path.join(outDir, 'release-manifest.json')));
  assert.throws(() => buildMinimalRelease({
    serverSource: sourceFile,
    outDir,
    expectedSha256: expected
  }), /already exists/);
  const checked = spawnSync(process.execPath, ['--check', path.join(outDir, 'server.js')], {
    encoding: 'utf8',
    windowsHide: true
  });
  assert.strictEqual(checked.status, 0, checked.stderr);
  for (const row of manifest.files) {
    const bytes = fs.readFileSync(path.join(outDir, row.path));
    assert.strictEqual(crypto.createHash('sha256').update(bytes).digest('hex'), row.sha256);
  }
  console.log('shard-minimal-release: passed ' + JSON.stringify({
    files: manifest.fileCount,
    contentHash: manifest.contentHash
  }));
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
