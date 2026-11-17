#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { lookupUserFromOwner } = require('../lib/shard-user-router');

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const row = process.argv.slice(2).find((value) => value.startsWith(prefix));
  return row ? row.slice(prefix.length) : fallback;
}

async function main() {
  const directoryFile = path.resolve(arg('directory', ''));
  const routePlanFile = path.resolve(arg('route-plan', ''));
  const secretFile = path.resolve(arg('secret-file', '/opt/xingyan-mainline/data/secret.key'));
  if (!fs.existsSync(directoryFile) || !fs.existsSync(routePlanFile)) {
    throw new Error('directory and route plan are required');
  }
  const directory = JSON.parse(fs.readFileSync(directoryFile, 'utf8'));
  const routePlan = JSON.parse(fs.readFileSync(routePlanFile, 'utf8'));
  const secret = fs.readFileSync(secretFile, 'utf8').trim();
  const result = await lookupUserFromOwner({
    directory,
    routePlan,
    secret,
    query: {
      id: arg('id', ''),
      username: arg('username', ''),
      phone: arg('phone', ''),
      email: arg('email', '')
    }
  });
  console.log(JSON.stringify({
    ok: result.ok,
    code: result.code || '',
    id: result.user && result.user.id || '',
    ownerShard: result.entry && result.entry.shard,
    ownerPort: result.ownerPort || 0
  }, null, 2));
  if (!result.ok) process.exitCode = 2;
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
