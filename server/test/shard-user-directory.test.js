'use strict';

const assert = require('assert');
const { buildRoutePlan } = require('../lib/shard-route-plan');
const {
  buildUserDirectory,
  createUserDirectoryResolver,
  verifyUserDirectory
} = require('../lib/shard-user-directory');

const users = [
  { id: 'u1', username: 'Alice', phone: '138-0000-0001' },
  { id: 'u2', username: 'bob', phone: '+86 13800000002', email: 'BOB@EXAMPLE.COM' },
  { id: 'u3', username: 'carol', phone: '' },
  { id: 'u4', username: 'dave', phone: '13800000004' }
];
const routePlan = buildRoutePlan({
  users,
  chats: [],
  shardCount: 7,
  ports: [7080, 7180, 7280, 7380, 7480, 7580, 7680],
  topologyId: 'user-directory-test',
  baselineDate: '2026-11-17',
  createdAt: '2026-11-17T00:00:00Z'
});

const directory = buildUserDirectory({ users, routePlan });
assert.strictEqual(directory.userCount, 4);
assert.strictEqual(directory.byShard.reduce((sum, count) => sum + count, 0), 4);
const resolver = createUserDirectoryResolver(directory);
assert.strictEqual(resolver.byId('u1').id, 'u1');
assert.strictEqual(resolver.byUsername(' ALICE ').id, 'u1');
assert.strictEqual(resolver.byPhone('+86 138-0000-0001').id, 'u1');
assert.strictEqual(resolver.byEmail('bob@example.com').id, 'u2');
assert.strictEqual(resolver.byId('missing'), null);
assert.strictEqual(verifyUserDirectory(directory, { users, routePlan }).ok, true);

assert.throws(() => buildUserDirectory({
  users: users.concat([{ id: 'u5', username: 'alice' }]),
  routePlan: buildRoutePlan({
    users: users.concat([{ id: 'u5', username: 'alice' }]),
    chats: [],
    shardCount: 7,
    ports: [7080, 7180, 7280, 7380, 7480, 7580, 7680],
    topologyId: 'user-directory-test',
    baselineDate: '2026-11-17',
    createdAt: '2026-11-17T00:00:00Z'
  })
}), /duplicate username/);

assert.throws(() => buildUserDirectory({
  users: users.concat([{ id: 'u5', username: 'other', phone: '13800000002' }]),
  routePlan: buildRoutePlan({
    users: users.concat([{ id: 'u5', username: 'other', phone: '13800000002' }]),
    chats: [],
    shardCount: 7,
    ports: [7080, 7180, 7280, 7380, 7480, 7580, 7680],
    topologyId: 'user-directory-test',
    baselineDate: '2026-11-17',
    createdAt: '2026-11-17T00:00:00Z'
  })
}), /duplicate phone/);

console.log('shard-user-directory: passed');
