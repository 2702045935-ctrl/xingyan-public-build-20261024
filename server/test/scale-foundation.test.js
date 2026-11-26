'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const {
  GroupMembershipDirectory
} = require('../lib/group-membership-directory');
const { LocalConnectionDirectory } = require('../lib/connection-directory');

function members(count, prefix) {
  return Array.from({ length: count }, (_, index) =>
    prefix + String(index).padStart(6, '0'));
}

function membershipTests() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-membership-'));
  const reads = [];
  const directory = new GroupMembershipDirectory({
    root,
    shardSize: 500,
    onShardRead: (chatId, shard) => reads.push({ chatId, shard })
  });
  try {
    const rows = members(10000, 'member-');
    const manifest = directory.install('c_people_10000', rows);
    assert.strictEqual(manifest.memberCount, 10000);
    assert.strictEqual(manifest.shardCount, 20);
    assert.strictEqual(directory.count('c_people_10000'), 10000);

    reads.length = 0;
    const first = directory.page('c_people_10000', 0, 100);
    assert.deepStrictEqual(first.members, rows.slice(0, 100));
    assert.strictEqual(first.nextCursor, 100);
    assert.strictEqual(first.hasMore, true);
    assert.deepStrictEqual(reads, [{ chatId: 'c_people_10000', shard: 0 }]);

    reads.length = 0;
    const middle = directory.page('c_people_10000', 7450, 120);
    assert.deepStrictEqual(middle.members, rows.slice(7450, 7570));
    assert.strictEqual(reads.length, 2);

    assert.strictEqual(directory.contains('c_people_10000', rows[0]), true);
    assert.strictEqual(directory.contains('c_people_10000', rows[4999]), true);
    assert.strictEqual(directory.contains('c_people_10000', rows[9999]), true);
    assert.strictEqual(directory.contains('c_people_10000', 'member-missing'), false);
    assert.deepStrictEqual(directory.all('c_people_10000'), rows);

    const replacement = members(3200, 'replacement-');
    const next = directory.install('c_people_10000', replacement);
    assert.strictEqual(next.memberCount, 3200);
    assert.strictEqual(next.shardCount, 7);
    assert.deepStrictEqual(directory.all('c_people_10000'), replacement);

    for (let index = 0; index < 32; index += 1) {
      directory.install('c_bulk_' + index, rows);
    }
    assert.strictEqual(directory.count('c_bulk_31'), 10000);
    const bulkPage = directory.page('c_bulk_31', 9900, 100);
    assert.strictEqual(bulkPage.members.length, 100);
    assert.strictEqual(bulkPage.hasMore, false);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
}

function connectionTests() {
  let clock = 1_700_000_000_000;
  const directory = new LocalConnectionDirectory({
    ttlMs: 10_000,
    maxConnections: 25_000,
    now: () => clock
  });
  for (let user = 0; user < 10_000; user += 1) {
    const userId = 'u_' + user;
    directory.register({
      userId,
      gatewayId: 'gw_' + (user % 200),
      deviceId: userId + '_a'
    });
    directory.register({
      userId,
      gatewayId: 'gw_' + ((user + 1) % 200),
      deviceId: userId + '_b'
    });
  }
  assert.deepStrictEqual(directory.stats(), {
    connections: 20000,
    users: 10000,
    gateways: 200,
    ttlMs: 10000
  });
  const first = directory.byUserId('u_42');
  assert.strictEqual(first.length, 2);
  assert.strictEqual(directory.gatewaysForUser('u_42').length, 2);
  assert.strictEqual(directory.unregister(first[0].connectionId), true);
  assert.strictEqual(directory.byUserId('u_42').length, 1);

  clock += 10_001;
  assert.strictEqual(directory.byUserId('u_42').length, 0);
  assert.strictEqual(directory.sweepExpired(), 19998);
  assert.strictEqual(directory.stats().connections, 0);
}

membershipTests();
connectionTests();
console.log('scale-foundation: passed');
