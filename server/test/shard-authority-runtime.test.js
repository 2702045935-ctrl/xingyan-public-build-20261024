'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { ShardAuthorityStore } = require('../lib/shard-authority-store');
const { ShardAuthorityRuntime } = require('../lib/shard-authority-runtime');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-authority-runtime-'));
try {
  const store = new ShardAuthorityStore({
    shardId: 0,
    topologyId: 'runtime-shards-7',
    databaseFile: path.join(root, 'authority.sqlite3'),
    writerEpoch: 1
  });
  const runtime = new ShardAuthorityRuntime({
    store,
    isDirectChat: (chatId) => chatId === 'direct-1',
    readEnabled: true,
    writeEnabled: true
  });
  assert.strictEqual(runtime.appendMessage('group-1', {
    id: 'g1',
    senderId: 'u1',
    seq: 1
  }).status, 'bypass');
  assert.strictEqual(runtime.readMessages('group-1'), null);

  let result = runtime.appendMessage('direct-1', {
    id: 'm1',
    senderId: 'u1',
    clientId: 'c1',
    seq: 1,
    content: 'one'
  }, { type: 'direct', title: 'Direct' });
  assert.strictEqual(result.status, 'applied');
  assert.deepStrictEqual(runtime.readMessages('direct-1').map((row) => row.id), ['m1']);

  result = runtime.replaceMessages('direct-1', [
    { id: 'm1', senderId: 'u1', seq: 1, content: 'one' },
    { id: 'm2', senderId: 'u2', seq: 2, content: 'two' }
  ], { type: 'direct', title: 'Direct' });
  assert.strictEqual(result.status, 'applied');
  assert.strictEqual(runtime.readMessages('direct-1').length, 2);
  assert.strictEqual(runtime.setClearCursor('u1', 'direct-1', 1).status, 'applied');
  assert.strictEqual(runtime.clearCursor('u1', 'direct-1'), 1);
  assert.strictEqual(runtime.setClearCursor('u1', 'group-1', 1).status, 'bypass');
  assert.strictEqual(runtime.clearCursor('u1', 'group-1'), 0);
  assert.strictEqual(runtime.verify().ok, true);
  runtime.close();
  console.log('shard-authority-runtime: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
