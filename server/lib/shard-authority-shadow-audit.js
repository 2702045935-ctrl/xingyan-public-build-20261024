'use strict';

const crypto = require('crypto');
const fs = require('fs');
const { DatabaseSync } = require('node:sqlite');

function stableJson(value) {
  if (Array.isArray(value)) return '[' + value.map(stableJson).join(',') + ']';
  if (value && typeof value === 'object') {
    return '{' + Object.keys(value).sort().map((key) =>
      JSON.stringify(key) + ':' + stableJson(value[key])
    ).join(',') + '}';
  }
  const encoded = JSON.stringify(value);
  return encoded === undefined ? 'null' : encoded;
}

function sha256(value) {
  return crypto.createHash('sha256').update(String(value || '')).digest('hex');
}

function auditShardAuthority(options) {
  const databaseFile = String(options && options.databaseFile || '');
  const snapshot = options && options.snapshot;
  if (!databaseFile) throw new Error('databaseFile is required');
  if (!snapshot || !Array.isArray(snapshot.snapshots)) {
    throw new Error('snapshot is required');
  }
  if (fs.existsSync(databaseFile + '-wal')
      || fs.existsSync(databaseFile + '-journal')) {
    throw new Error('authority database must be checkpointed before audit');
  }
  const db = new DatabaseSync(databaseFile, { readOnly: true });
  const issues = [];
  const chats = [];
  try {
    const expectedById = new Map(snapshot.snapshots.map((chat) => [
      String(chat.chatId),
      chat
    ]));
    const messageRows = db.prepare(`
      SELECT message_id, chat_id, seq, payload_json
      FROM reliable_messages
      ORDER BY chat_id, seq
    `).all();
    const actualByChat = new Map();
    for (const row of messageRows) {
      const chatId = String(row.chat_id);
      if (!actualByChat.has(chatId)) actualByChat.set(chatId, []);
      actualByChat.get(chatId).push(row);
    }

    for (const [chatId, expected] of expectedById.entries()) {
      const actual = actualByChat.get(chatId) || [];
      const expectedMessages = Array.isArray(expected.messages) ? expected.messages : [];
      if (actual.length !== expectedMessages.length) {
        issues.push({
          code: 'message-count',
          chatId,
          expected: expectedMessages.length,
          actual: actual.length
        });
      }
      const count = Math.min(actual.length, expectedMessages.length);
      for (let index = 0; index < count; index += 1) {
        const left = expectedMessages[index];
        const right = actual[index];
        if (String(left.id) !== String(right.message_id)
            || Number(left.seq) !== Number(right.seq)) {
          issues.push({
            code: 'message-identity',
            chatId,
            index,
            expectedId: String(left.id),
            actualId: String(right.message_id),
            expectedSeq: Number(left.seq),
            actualSeq: Number(right.seq)
          });
          continue;
        }
        if (sha256(stableJson(left)) !== sha256(String(right.payload_json))) {
          issues.push({
            code: 'message-content',
            chatId,
            messageId: String(left.id),
            seq: Number(left.seq)
          });
        }
      }
      const state = db.prepare(
        'SELECT seq, payload_json FROM chat_state WHERE chat_id = ?'
      ).get(chatId);
      if (!state) {
        issues.push({ code: 'missing-chat-state', chatId });
      } else {
        if (Number(state.seq) !== expectedMessages.length) {
          issues.push({
            code: 'chat-state-sequence',
            chatId,
            expected: expectedMessages.length,
            actual: Number(state.seq)
          });
        }
        const payload = JSON.parse(state.payload_json);
        const last = expectedMessages[expectedMessages.length - 1];
        if (String(payload.lastMessageId || '') !== String(last && last.id || '')) {
          issues.push({
            code: 'chat-last-message',
            chatId,
            expected: String(last && last.id || ''),
            actual: String(payload.lastMessageId || '')
          });
        }
      }
      chats.push({
        chatId,
        expectedMessages: expectedMessages.length,
        actualMessages: actual.length,
        ok: !issues.some((issue) => issue.chatId === chatId)
      });
    }
    for (const chatId of actualByChat.keys()) {
      if (!expectedById.has(chatId)) {
        issues.push({
          code: 'unexpected-chat',
          chatId,
          actual: actualByChat.get(chatId).length
        });
      }
    }
    const sequenceMismatch = db.prepare(`
      SELECT s.chat_id, s.last_seq, COALESCE(MAX(m.seq), 0) AS max_seq
      FROM chat_sequence s
      LEFT JOIN reliable_messages m ON m.chat_id = s.chat_id
      GROUP BY s.chat_id
      HAVING s.last_seq != COALESCE(MAX(m.seq), 0)
    `).all();
    for (const row of sequenceMismatch) {
      issues.push({
        code: 'sequence-row-mismatch',
        chatId: String(row.chat_id),
        lastSeq: Number(row.last_seq),
        maxSeq: Number(row.max_seq)
      });
    }
  } finally {
    db.close();
  }
  return {
    version: 1,
    ok: issues.length === 0,
    databaseFile,
    chats: chats.length,
    messages: snapshot.messages,
    issues,
    chatRows: chats
  };
}

module.exports = { auditShardAuthority };
