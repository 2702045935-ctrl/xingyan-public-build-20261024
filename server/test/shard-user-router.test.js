'use strict';

const assert = require('assert');
const { buildRoutePlan } = require('../lib/shard-route-plan');
const { buildUserDirectory } = require('../lib/shard-user-directory');
const { resolveDirectoryEntry, lookupUserFromOwner } = require('../lib/shard-user-router');

const users = [
  { id: 'u1', username: 'alice', phone: '13800000001', nickname: 'Alice' },
  { id: 'u2', username: 'bob', phone: '13800000002', nickname: 'Bob' }
];
const ports = [7080, 7180, 7280, 7380, 7480, 7580, 7680];
const routePlan = buildRoutePlan({
  users,
  chats: [],
  shardCount: 7,
  ports,
  topologyId: 'user-router-test',
  baselineDate: '2026-11-17',
  createdAt: '2026-11-17T00:00:00Z'
});
const directory = buildUserDirectory({ users, routePlan });
const originalFetch = global.fetch;

global.fetch = async (url, options) => {
  const parsed = new URL(url);
  const port = Number(parsed.port);
  const body = JSON.parse(options.body);
  const user = users.find((row) => row.id === body.userId);
  const expectedEntry = directory.entries.find((row) => row.id === body.userId);
  if (port !== ports[expectedEntry.shard]) {
    return { ok: false, status: 404, json: async () => ({ ok: false, error: 'wrong shard' }) };
  }
  return {
    ok: true,
    status: 200,
    json: async () => ({
      ok: true,
      data: { user, owner: expectedEntry.shard }
    })
  };
};

async function main() {
  assert.strictEqual(resolveDirectoryEntry(directory, { id: 'u1' }).id, 'u1');
  assert.strictEqual(resolveDirectoryEntry(directory, { username: 'BOB' }).id, 'u2');
  assert.strictEqual(resolveDirectoryEntry(directory, { phone: '+86 138-0000-0001' }).id, 'u1');

  const result = await lookupUserFromOwner({
    directory,
    routePlan,
    secret: 'test',
    query: { username: 'alice' }
  });
  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.user.id, 'u1');
  assert.strictEqual(result.ownerPort, ports[result.entry.shard]);

  const noPlan = Object.assign({}, routePlan, { hash: '0'.repeat(64) });
  await assert.rejects(() => lookupUserFromOwner({
    directory,
    routePlan: noPlan,
    secret: 'test',
    query: { id: 'u1' }
  }), /route plan does not match/);

  console.log('shard-user-router: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
}).finally(() => {
  global.fetch = originalFetch;
});
