'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { auditMessageShardSet } = require('../lib/message-consistency-audit-matrix');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-message-audit-matrix-'));

function message(id, chatId, seq, content) {
  return {
    id,
    chatId,
    seq,
    senderId: 'u1',
    clientId: `client-${id}`,
    kind: 'text',
    content,
    createdAt: `2026-11-15T00:00:0${seq}.000Z`
  };
}

function writeMessages(dataDir, chatId, rows) {
  fs.mkdirSync(path.join(dataDir, 'messages'), { recursive: true });
  fs.writeFileSync(path.join(dataDir, 'messages', chatId + '.jsonl'),
    rows.map((row) => JSON.stringify(row)).join('\n') + '\n');
}

function digestTree(directory) {
  const rows = [];
  const walk = (current, prefix) => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })
      .sort((left, right) => left.name.localeCompare(right.name))) {
      const full = path.join(current, entry.name);
      const relative = prefix ? prefix + '/' + entry.name : entry.name;
      if (entry.isDirectory()) walk(full, relative);
      else rows.push({
        path: relative,
        sha256: crypto.createHash('sha256').update(fs.readFileSync(full)).digest('hex')
      });
    }
  };
  walk(directory, '');
  return rows;
}

async function main() {
  try {
    const shardA = path.join(root, 'shard-a');
    const shardB = path.join(root, 'shard-b');
    writeMessages(shardA, 'chat-a', [message('message-a-1', 'chat-a', 1, 'a')]);
    writeMessages(shardB, 'chat-b', [message('message-b-1', 'chat-b', 1, 'b')]);
    const beforeA = digestTree(shardA);
    const beforeB = digestTree(shardB);

    const clean = await auditMessageShardSet({
      shards: [
        { sourceId: 'shard-a', dataDir: shardA },
        { sourceId: 'shard-b', dataDir: shardB }
      ],
      expectedMessages: 2
    });
    assert.strictEqual(clean.ok, true, JSON.stringify(clean.issues, null, 2));
    assert.strictEqual(clean.shardCount, 2);
    assert.strictEqual(clean.messageCount, 2);
    assert.deepStrictEqual(digestTree(shardA), beforeA);
    assert.deepStrictEqual(digestTree(shardB), beforeB);

    const duplicateChat = path.join(root, 'duplicate-chat');
    writeMessages(duplicateChat, 'chat-a',
      [message('message-a-other', 'chat-a', 1, 'other shard')]);
    const chatCollision = await auditMessageShardSet({
      shards: [
        { sourceId: 'shard-a', dataDir: shardA },
        { sourceId: 'duplicate-chat', dataDir: duplicateChat }
      ]
    });
    assert.strictEqual(chatCollision.ok, false);
    assert.strictEqual(
      chatCollision.issues.filter((row) => row.kind === 'chat-id-cross-shard').length,
      1
    );

    const duplicateMessage = path.join(root, 'duplicate-message');
    writeMessages(duplicateMessage, 'chat-c',
      [message('message-a-1', 'chat-c', 1, 'same id')]);
    const messageCollision = await auditMessageShardSet({
      shards: [
        { sourceId: 'shard-a', dataDir: shardA },
        { sourceId: 'duplicate-message', dataDir: duplicateMessage }
      ]
    });
    assert.strictEqual(messageCollision.ok, false);
    assert.strictEqual(
      messageCollision.issues.filter((row) => row.kind === 'message-id-cross-shard').length,
      1
    );

    const countMismatch = await auditMessageShardSet({
      shards: [
        { sourceId: 'shard-a', dataDir: shardA },
        { sourceId: 'shard-b', dataDir: shardB }
      ],
      expectedMessages: 3
    });
    assert.strictEqual(countMismatch.ok, false);
    assert.strictEqual(countMismatch.countMatches, false);

    console.log('message-consistency-audit-matrix: passed');
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
