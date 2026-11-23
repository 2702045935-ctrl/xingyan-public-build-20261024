#!/usr/bin/env node
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const file = path.resolve(process.argv[2] || '');
if (!file) throw new Error('usage: patch-production-control-api.js SERVER_JS');
let source = fs.readFileSync(file, 'utf8');
const marker = 'FLEET_CONTROL_API_V1';
if (!source.includes(marker)) {
  const anchor = "  if (parts[0] === 'ops' && parts[1] !== 'account') {";
  const index = source.indexOf(anchor);
  if (index < 0) throw new Error('ops dispatch anchor not found');
  const patch = `  /* ${marker}: minimal independent control-plane adapter. */
  if (parts[0] === 'ops'
      && (parts[1] === 'fleet' || parts[1] === 'shardmaintenance')) {
    const { createFleetControlHttp } = require('./lib/fleet-control-http');
    const handled = await createFleetControlHttp({
      ok, fail, readBody, audit, writeJson, currentOps, opsConfirmOk, root: ROOT
    })(req, res, parts, method);
    if (handled) return;
  }

`;
  source = source.slice(0, index) + patch + source.slice(index);
}
const temporary = file + '.fleet-' + process.pid + '.tmp.js';
fs.writeFileSync(temporary, source, 'utf8');
const checked = spawnSync(process.execPath, ['--check', temporary], {
  encoding: 'utf8',
  windowsHide: true
});
if (checked.status !== 0) {
  try { fs.unlinkSync(temporary); } catch (_) {}
  throw new Error(checked.stderr || checked.stdout || 'server patch syntax failed');
}
const backup = file + '.before-fleet-' + Date.now();
fs.copyFileSync(file, backup);
fs.renameSync(temporary, file);
console.log(JSON.stringify({
  ok: true,
  file,
  backup,
  sha256: crypto.createHash('sha256').update(source).digest('hex')
}));
