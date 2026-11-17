'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { ShardAuthorityStore } = require('../lib/shard-authority-store');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-authority-store-'));
const databaseFile = path.join(root, 'shard-2.sqlite3');
let epoch = 7;
let owner = 'cell-a';
const lease = {
  validate(shard) {
    return shard === 2 && owner === 'cell-a'
      ? { ok: true, lease: { shard: 2, ownerId: owner, epoch } }
      : { ok: false, reason: 'not-owner' };
  }
};

try {
  let store = new ShardAuthorityStore({
    shardId: 2,
    topologyId: 'test-shards-7',
    databaseFile,
    leaseManager: lease,
    now: () => '2026-11-17T00:00:00.000Z',
    uid: (() => {
      let sequence = 0;
      return (prefix) => prefix + '-' + (++sequence);
    })()
  });

  let result = store.appendMessage({
    id: 'm-1',
    chatId: 'chat-1',
    senderId: 'user-1',
    clientId: 'client-1',
    kind: 'text',
    content: 'hello',
    createdAt: '2026-11-17T00:00:01.000Z',
    chatState: { type: 'direct', title: 'Alice' }
  });
  assert.strictEqual(result.status, 'applied');
  assert.strictEqual(result.seq, 1);

  result = store.appendMessage({
    id: 'different-local-id',
    chatId: 'chat-1',
    senderId: 'user-1',
    clientId: 'client-1',
    content: 'retry must not append',
    createdAt: '2026-11-17T00:00:02.000Z'
  });
  assert.strictEqual(result.status, 'duplicate');
  assert.strictEqual(result.seq, 1);

  result = store.appendMessage({
    id: 'm-2',
    chatId: 'chat-1',
    senderId: 'user-2',
    clientId: 'client-2',
    kind: 'text',
    content: 'world',
    createdAt: '2026-11-17T00:00:03.000Z'
  });
  assert.strictEqual(result.status, 'applied');
  assert.strictEqual(result.seq, 2);
  assert.strictEqual(store.readChat('chat-1').state.title, 'Alice');
  assert.strictEqual(store.readChat('chat-1').seq, 2);
  assert.strictEqual(store.messagesAfter('chat-1', 0, 10).length, 2);
  assert.strictEqual(store.verify().ok, true);

  store.checkpoint();
  store.close();
  store = new ShardAuthorityStore({
    shardId: 2,
    topologyId: 'test-shards-7',
    databaseFile,
    leaseManager: lease
  });
  assert.strictEqual(store.readChat('chat-1').seq, 2);
  assert.strictEqual(store.verify().ok, true);

  epoch = 8;
  owner = 'cell-b';
  result = store.appendMessage({
    chatId: 'chat-1',
    senderId: 'user-3',
    clientId: 'stale-writer',
    content: 'must be fenced'
  });
  assert.strictEqual(result.status, 'fenced');
  assert.strictEqual(store.messagesAfter('chat-1', 0, 10).length, 2);
  store.close();
  console.log('shard-authority-store: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
