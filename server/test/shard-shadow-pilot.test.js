'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { runShadowPilot } = require('../tools/shard-shadow-pilot');

const root = path.resolve(__dirname, '..');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-shadow-pilot-test-'));
const source = path.join(temp, 'source');
const work = path.join(temp, 'shadow');
fs.mkdirSync(source, { recursive: true });

try {
  const users = [{ id: 'u1', username: 'u1' }, { id: 'u2', username: 'u2' }];
  const chats = [{
    id: 'c1',
    type: 'direct',
    memberIds: ['u1', 'u2'],
    pinnedFor: ['u1'],
    flaggedUnread: ['u2']
  }];
  const moments = [{
    id: 'm1',
    authorId: 'u1',
    content: 'test',
    likes: [{ userId: 'u2', at: '2026-11-16T00:00:00Z' }],
    comments: []
  }];
  fs.writeFileSync(path.join(source, 'users.json'), JSON.stringify({ users }));
  fs.writeFileSync(path.join(source, 'friendships.json'), JSON.stringify({
    friendships: [{
      id: 'f1',
      fromId: 'u1',
      toId: 'u2',
      status: 'accepted'
    }]
  }));
  fs.writeFileSync(path.join(source, 'chats.json'), JSON.stringify({ chats }));
  fs.writeFileSync(path.join(source, 'reads.json'), JSON.stringify({
    reads: { u1: { c1: 3 } },
    cleared: {}
  }));
  fs.writeFileSync(path.join(source, 'friendmeta.json'), JSON.stringify({
    byOwner: { u1: { u2: { remark: 'B' } } }
  }));
  fs.writeFileSync(path.join(source, 'moments.json'), JSON.stringify({ moments }));
  fs.writeFileSync(path.join(source, 'moment-notices.json'), JSON.stringify({
    items: [],
    seen: {}
  }));

  const result = runShadowPilot({
    sourceDir: source,
    workDir: work,
    manifestFile: path.join(root, 'shard-runtime-production.json'),
    topologyFile: path.join(root, 'shard-topologies.json')
  });
  result.close();
  assert.strictEqual(result.ok, true, JSON.stringify(result));
  assert.deepStrictEqual(result.failures, []);
  assert.strictEqual(result.audit.ok, true);
  assert.strictEqual(result.clusterAudit.ok, true);
  assert.deepStrictEqual(result.duplicateOwners, []);
  assert.strictEqual(result.sourceCounts.users, 2);
  assert.strictEqual(result.sourceCounts.chats, 1);
  assert.strictEqual(
    result.owners.users.reduce((sum, value) => sum + value, 0),
    2
  );
  assert.strictEqual(
    result.owners.chats.reduce((sum, value) => sum + value, 0),
    1
  );
  console.log('shard-shadow-pilot: passed');
} finally {
  fs.rmSync(temp, { recursive: true, force: true });
}
