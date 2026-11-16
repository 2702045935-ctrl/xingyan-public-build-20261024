#!/usr/bin/env node
'use strict';

const path = require('path');
const { ShardMaintenanceStore } = require('../lib/shard-maintenance');

const args = process.argv.slice(2);

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const row = args.find((value) => value.startsWith(prefix));
  return row ? row.slice(prefix.length) : fallback;
}

function usage() {
  return [
    'shard-maintenance-executor.js --file=STATE_FILE --status',
    'shard-maintenance-executor.js --file=STATE_FILE --claim --id=ROLLOUT --shard=0',
    'shard-maintenance-executor.js --file=STATE_FILE --complete --id=ROLLOUT --shard=0'
      + ' --after-code-sha256=SHA256 --after-pid=PID',
    'shard-maintenance-executor.js --file=STATE_FILE --fail --id=ROLLOUT --shard=0'
      + ' --reason=TEXT',
    '',
    'This tool only claims and reports shard execution. It never starts a service,',
    'copies files, or rolls back automatically.'
  ].join('\n');
}

function main() {
  const file = arg('file', '/opt/xingyan-mainline/data/shard-maintenance.json');
  const id = arg('id', '');
  const shardId = Number(arg('shard', '-1'));
  const actor = {
    id: 'shard-executor',
    username: arg('actor', 'shard-executor'),
    name: arg('actor-name', '分片执行器'),
    role: 'automation'
  };
  const store = new ShardMaintenanceStore(path.resolve(file));

  if (args.includes('--help')) {
    console.log(usage());
    return;
  }
  if (args.includes('--status')) {
    const active = store.list().find((row) =>
      ['draft', 'ready', 'awaiting_execution', 'deploying',
        'awaiting_health', 'awaiting_approval', 'paused'].includes(row.status)
    ) || store.list()[0] || null;
    console.log(JSON.stringify({
      ok: true,
      executorActionRequired: active && active.status === 'awaiting_execution',
      rollout: active
    }, null, 2));
    return;
  }
  if (!id) throw new Error('--id=ROLLOUT is required');
  if (!Number.isInteger(shardId) || shardId < 0) {
    throw new Error('--shard=N is required');
  }

  let rollout;
  if (args.includes('--claim')) {
    rollout = store.transition(id, 'claim', { shardId }, actor);
  } else if (args.includes('--complete')) {
    rollout = store.transition(id, 'complete', {
      shardId,
      afterCodeSha256: arg('after-code-sha256', ''),
      afterPid: Number(arg('after-pid', '0')),
      systemdActive: arg('systemd-active', '1') === '1'
    }, actor);
  } else if (args.includes('--fail')) {
    rollout = store.transition(id, 'fail', {
      shardId,
      reason: arg('reason', '执行器失败')
    }, actor);
  } else {
    throw new Error('use --claim, --complete, --fail or --status\n\n' + usage());
  }
  console.log(JSON.stringify({
    ok: true,
    rollout,
    note: 'execution state recorded only; service actions are external'
  }, null, 2));
}

try {
  main();
} catch (error) {
  console.error(error.stack || error);
  process.exitCode = 1;
}
