#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { runDualCellShadowProbe } = require('../lib/dual-cell-shadow-probe');

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const row = process.argv.slice(2).find((value) => value.startsWith(prefix));
  return row ? row.slice(prefix.length) : fallback;
}

function jsonEnv(name) {
  if (!name || !process.env[name]) return {};
  const value = JSON.parse(process.env[name]);
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(name + ' must contain a JSON object');
  }
  return value;
}

async function main() {
  const planFile = arg('plan', '');
  const requestsFile = arg('requests', '');
  const out = arg('out', '');
  if (!planFile || !requestsFile) {
    throw new Error('usage: dual-cell-shadow-probe.js --plan=FILE '
      + '--requests=FILE [--out=REPORT] '
      + '[--headers-a-env=ENV_NAME] [--headers-b-env=ENV_NAME]');
  }
  const plan = JSON.parse(fs.readFileSync(path.resolve(planFile), 'utf8'));
  const requestData = JSON.parse(fs.readFileSync(path.resolve(requestsFile), 'utf8'));
  const requests = Array.isArray(requestData) ? requestData : requestData.requests || [];
  const report = await runDualCellShadowProbe({
    plan,
    requests,
    headersA: jsonEnv(arg('headers-a-env', '')),
    headersB: jsonEnv(arg('headers-b-env', ''))
  });
  const text = JSON.stringify(report, null, 2);
  if (out) {
    const file = path.resolve(out);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const temporary = file + '.' + process.pid + '.tmp';
    fs.writeFileSync(temporary, text, 'utf8');
    fs.renameSync(temporary, file);
    console.log(JSON.stringify({
      ok: report.ok,
      compared: report.compared,
      diffs: report.diffs.length,
      errors: report.errors.length,
      circuitOpen: report.circuitOpen,
      fingerprint: report.fingerprint,
      out: file
    }, null, 2));
  } else {
    process.stdout.write(text);
  }
  if (!report.ok) process.exitCode = 2;
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.stack || error);
    process.exitCode = 1;
  });
}

module.exports = { main };
