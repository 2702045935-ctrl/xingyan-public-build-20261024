'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const {
  runMigration
} = require('../tools/group-membership-shadow-migration');

async function main() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-member-shadow-'));
  try {
    const largeMembers = Array.from({ length: 10000 }, (_, index) =>
      'u_' + String(index).padStart(6, '0'));
    const smallMembers = ['u_small_a', 'u_small_b', 'u_small_c'];
    const chatsFile = path.join(root, 'chats.json');
    fs.writeFileSync(chatsFile, JSON.stringify({
      chats: [
        {
          id: 'c_large',
          type: 'group',
          name: 'large',
          memberIds: largeMembers
        },
        {
          id: 'c_small',
          type: 'group',
          name: 'small',
          memberIds: smallMembers
        },
        {
          id: 'c_direct',
          type: 'direct',
          name: 'direct',
          memberIds: ['u_a', 'u_b']
        }
      ]
    }), 'utf8');

    const dryRun = await runMigration({
      chatsFile,
      root: path.join(root, 'shadow-dry'),
      limit: 0,
      apply: false
    });
    assert.strictEqual(dryRun.totalGroups, 2);
    assert.strictEqual(dryRun.selectedGroups, 2);
    assert.strictEqual(dryRun.totalMembers, 10003);
    assert.strictEqual(dryRun.pass, true);
    assert.strictEqual(fs.existsSync(path.join(root, 'shadow-dry', 'groups')), false);

    const applied = await runMigration({
      chatsFile,
      root: path.join(root, 'shadow-applied'),
      limit: 0,
      shardSize: 500,
      apply: true
    });
    assert.strictEqual(applied.selectedGroups, 2);
    assert.strictEqual(applied.totalMembers, 10003);
    assert.strictEqual(applied.pass, true);
    assert.strictEqual(applied.groups[0].shardCount, 20);
    assert.ok(applied.groups[0].generation);
    assert.strictEqual(applied.groups[1].shardCount, 1);
    assert.ok(fs.existsSync(path.join(
      root,
      'shadow-applied',
      'groups'
    )));
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
  console.log('group-membership-shadow-migration: passed');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
