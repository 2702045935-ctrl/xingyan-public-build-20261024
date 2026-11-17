#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const {
  buildUserDirectory,
  verifyUserDirectory
} = require('../lib/shard-user-directory');

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const row = process.argv.slice(2).find((value) => value.startsWith(prefix));
  return row ? row.slice(prefix.length) : fallback;
}

function main() {
  const usersFile = arg('users', '/opt/xingyan-mainline/data/users.json');
  const routePlanFile = arg('route-plan', '/opt/xingyan-mainline/releases/20261116-shard-baseline/route-plan.json');
  const out = arg('out', '');
  const usersPayload = JSON.parse(fs.readFileSync(usersFile, 'utf8'));
  const users = Array.isArray(usersPayload)
    ? usersPayload
    : (usersPayload.users || []);
  const routePlan = JSON.parse(fs.readFileSync(routePlanFile, 'utf8'));
  const directory = buildUserDirectory({ users, routePlan });
  const verification = verifyUserDirectory(directory, { users, routePlan });
  if (!verification.ok) {
    throw new Error('user directory verification failed: ' + JSON.stringify(verification.failures));
  }
  if (out) {
    const file = path.resolve(out);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const temporary = file + '.' + process.pid + '.tmp';
    fs.writeFileSync(temporary, JSON.stringify(directory, null, 2), 'utf8');
    fs.renameSync(temporary, file);
  }
  console.log(JSON.stringify({
    ok: true,
    userCount: directory.userCount,
    byShard: directory.byShard,
    hash: directory.hash,
    out: out ? path.resolve(out) : ''
  }, null, 2));
}

try {
  main();
} catch (error) {
  console.error(error.stack || error);
  process.exitCode = 1;
}
