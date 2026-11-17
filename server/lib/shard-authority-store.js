'use strict';

const { MessageReliabilityStore } = require('./message-reliability');

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

class ShardAuthorityStore {
  constructor(options) {
    const opts = options || {};
    this.shardId = Number(opts.shardId);
    if (!Number.isInteger(this.shardId) || this.shardId < 0) {
      throw new Error('shardId is required');
    }
    this.topologyId = String(opts.topologyId || '');
    if (!this.topologyId) throw new Error('topologyId is required');
    this.leaseManager = opts.leaseManager || null;
    this.staticEpoch = Number(opts.writerEpoch);
    if (!this.leaseManager
        && (!Number.isSafeInteger(this.staticEpoch) || this.staticEpoch <= 0)) {
      throw new Error('leaseManager or a positive writerEpoch is required');
    }

    this.messages = new MessageReliabilityStore({
      databaseFile: opts.databaseFile,
      now: opts.now,
      uid: opts.uid
    });
    this.db = this.messages.db;
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS shard_authority (
        singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
        shard_id INTEGER NOT NULL,
        topology_id TEXT NOT NULL,
        schema_version INTEGER NOT NULL,
        updated_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS chat_state (
        chat_id TEXT PRIMARY KEY,
        seq INTEGER NOT NULL DEFAULT 0,
        payload_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    `);
    const at = new Date().toISOString();
    const current = this.db.prepare(
      'SELECT shard_id, topology_id FROM shard_authority WHERE singleton = 1'
    ).get();
    if (current
        && (Number(current.shard_id) !== this.shardId
          || String(current.topology_id) !== this.topologyId)) {
      this.messages.close();
      throw new Error('shard authority identity mismatch');
    }
    this.db.prepare(`
      INSERT INTO shard_authority
        (singleton, shard_id, topology_id, schema_version, updated_at)
      VALUES (1, ?, ?, 1, ?)
      ON CONFLICT(singleton) DO UPDATE SET
        schema_version = excluded.schema_version,
        updated_at = excluded.updated_at
    `).run(this.shardId, this.topologyId, at);
  }

  writerLease() {
    if (!this.leaseManager) {
      return { ok: true, epoch: this.staticEpoch };
    }
    const lease = this.leaseManager.validate(this.shardId);
    if (!lease || !lease.ok || !lease.lease) {
      return {
        ok: false,
        reason: String(lease && lease.reason || 'lease-unavailable')
      };
    }
    return {
      ok: true,
      epoch: Number(lease.lease.epoch) || 0,
      ownerId: String(lease.lease.ownerId || '')
    };
  }

  assertLease(epoch) {
    const lease = this.writerLease();
    if (!lease.ok || Number(lease.epoch) !== Number(epoch)) {
      throw new Error('writer is fenced');
    }
    return lease;
  }

  appendMessage(input) {
    const message = Object.assign({}, input || {});
    const chatId = String(message.chatId || '');
    const senderId = String(message.senderId || '');
    const clientId = String(message.clientId || '').slice(0, 80);
    if (!chatId || !senderId) throw new Error('chatId and senderId are required');
    const before = this.writerLease();
    if (!before.ok) return Object.assign({ status: 'fenced' }, before);

    return this.messages.transaction(() => {
      if (clientId) {
        const duplicate = this.db.prepare(`
          SELECT * FROM reliable_messages
          WHERE chat_id = ? AND sender_id = ? AND client_id = ?
        `).get(chatId, senderId, clientId);
        if (duplicate) {
          return {
            status: 'duplicate',
            duplicate: true,
            message: JSON.parse(duplicate.payload_json),
            seq: Number(duplicate.seq),
            eventId: ''
          };
        }
      }

      const messageId = String(message.id || this.messages.uid('m'));
      const sameId = this.db.prepare(
        'SELECT * FROM reliable_messages WHERE message_id = ?'
      ).get(messageId);
      if (sameId) {
        return {
          status: 'duplicate',
          duplicate: true,
          message: JSON.parse(sameId.payload_json),
          seq: Number(sameId.seq),
          eventId: ''
        };
      }

      const sequence = this.db.prepare(
        'SELECT last_seq FROM chat_sequence WHERE chat_id = ?'
      ).get(chatId);
      const seq = (sequence ? Number(sequence.last_seq) || 0 : 0) + 1;
      const createdAt = String(message.createdAt || this.messages.now());
      const persisted = Object.assign({}, message, {
        id: messageId,
        chatId,
        senderId,
        seq,
        createdAt
      });
      delete persisted.chatState;
      if (clientId) persisted.clientId = clientId;

      this.db.prepare(`
        INSERT INTO chat_sequence(chat_id, last_seq, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(chat_id) DO UPDATE SET
          last_seq = excluded.last_seq,
          updated_at = excluded.updated_at
      `).run(chatId, seq, createdAt);
      this.db.prepare(`
        INSERT INTO reliable_messages
          (message_id, chat_id, sender_id, client_id, seq, payload_json, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `).run(messageId, chatId, senderId, clientId || null, seq,
        stableJson(persisted), createdAt);

      const previous = this.db.prepare(
        'SELECT payload_json FROM chat_state WHERE chat_id = ?'
      ).get(chatId);
      const previousState = previous ? JSON.parse(previous.payload_json) : {};
      const state = Object.assign({}, previousState, message.chatState || {}, {
        chatId,
        seq,
        lastMessageId: messageId,
        lastSenderId: senderId,
        lastMessageAt: createdAt,
        updatedAt: createdAt
      });
      this.db.prepare(`
        INSERT INTO chat_state(chat_id, seq, payload_json, updated_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(chat_id) DO UPDATE SET
          seq = excluded.seq,
          payload_json = excluded.payload_json,
          updated_at = excluded.updated_at
      `).run(chatId, seq, stableJson(state), createdAt);

      const eventId = this.messages.appendEvent(
        'message.created',
        messageId,
        seq,
        { message: persisted, chatState: state },
        createdAt
      );
      this.assertLease(before.epoch);
      return {
        status: 'applied',
        duplicate: false,
        message: persisted,
        chatState: state,
        seq,
        eventId
      };
    });
  }

  updateChat(chatId, patch, expectedSeq) {
    const chat = String(chatId || '');
    if (!chat) throw new Error('chatId is required');
    const before = this.writerLease();
    if (!before.ok) return Object.assign({ status: 'fenced' }, before);
    return this.messages.transaction(() => {
      const row = this.db.prepare(
        'SELECT seq, payload_json FROM chat_state WHERE chat_id = ?'
      ).get(chat);
      const currentSeq = row ? Number(row.seq) || 0 : 0;
      if (expectedSeq != null && Number(expectedSeq) !== currentSeq) {
        return { status: 'version-conflict', currentSeq };
      }
      const current = row ? JSON.parse(row.payload_json) : {};
      const state = Object.assign({}, current, patch || {}, {
        chatId: chat,
        seq: currentSeq,
        updatedAt: this.messages.now()
      });
      this.db.prepare(`
        INSERT INTO chat_state(chat_id, seq, payload_json, updated_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(chat_id) DO UPDATE SET
          payload_json = excluded.payload_json,
          updated_at = excluded.updated_at
      `).run(chat, currentSeq, stableJson(state), state.updatedAt);
      const eventId = this.messages.appendEvent(
        'chat.updated',
        chat,
        currentSeq,
        state,
        state.updatedAt
      );
      this.assertLease(before.epoch);
      return { status: 'applied', chatState: state, eventId };
    });
  }

  importChatSnapshot(chatId, messages, chatState) {
    const chat = String(chatId || '');
    if (!chat) throw new Error('chatId is required');
    const rows = (Array.isArray(messages) ? messages : []).map((message) =>
      Object.assign({}, message || {})
    );
    rows.forEach((message, index) => {
      if (!message.id) throw new Error('snapshot message id is required');
      if (Number(message.seq) !== index + 1) {
        throw new Error('snapshot sequence must be contiguous from 1');
      }
    });
    const ids = new Set();
    const sequence = new Set();
    for (const message of rows) {
      const id = String(message.id);
      if (ids.has(id)) throw new Error('duplicate snapshot message id: ' + id);
      if (sequence.has(Number(message.seq))) {
        throw new Error('duplicate snapshot sequence');
      }
      ids.add(id);
      sequence.add(Number(message.seq));
    }

    const before = this.writerLease();
    if (!before.ok) return Object.assign({ status: 'fenced' }, before);
    return this.messages.transaction(() => {
      const existing = this.db.prepare(
        'SELECT message_id, seq, payload_json FROM reliable_messages WHERE chat_id = ? ORDER BY seq'
      ).all(chat);
      if (existing.length) {
        const same = existing.length === rows.length
          && existing.every((row, index) => {
            const next = rows[index];
            return String(row.message_id) === String(next.id)
              && Number(row.seq) === Number(next.seq)
              && row.payload_json === stableJson(next);
          });
        if (same) {
          return {
            status: 'duplicate',
            imported: 0,
            existing: rows.length,
            chatState: this.readChat(chat)
          };
        }
        throw new Error('conflicting snapshot for chat ' + chat);
      }

      const insert = this.db.prepare(`
        INSERT INTO reliable_messages
          (message_id, chat_id, sender_id, client_id, seq, payload_json, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `);
      for (const message of rows) {
        const clientId = String(message.clientId || '').slice(0, 80) || null;
        insert.run(
          String(message.id),
          chat,
          String(message.senderId || 'unknown'),
          clientId,
          Number(message.seq),
          stableJson(message),
          String(message.createdAt || this.messages.now())
        );
        this.messages.appendEvent(
          'message.imported',
          String(message.id),
          Number(message.seq),
          message,
          String(message.createdAt || this.messages.now())
        );
      }
      const lastSeq = rows.length;
      const updatedAt = this.messages.now();
      this.db.prepare(`
        INSERT INTO chat_sequence(chat_id, last_seq, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(chat_id) DO UPDATE SET
          last_seq = excluded.last_seq,
          updated_at = excluded.updated_at
      `).run(chat, lastSeq, updatedAt);
      const state = Object.assign({}, chatState || {}, {
        chatId: chat,
        seq: lastSeq,
        updatedAt
      });
      this.db.prepare(`
        INSERT INTO chat_state(chat_id, seq, payload_json, updated_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(chat_id) DO UPDATE SET
          seq = excluded.seq,
          payload_json = excluded.payload_json,
          updated_at = excluded.updated_at
      `).run(chat, lastSeq, stableJson(state), updatedAt);
      this.assertLease(before.epoch);
      return {
        status: 'applied',
        imported: rows.length,
        existing: 0,
        chatState: state
      };
    });
  }

  readChat(chatId) {
    const row = this.db.prepare(
      'SELECT seq, payload_json FROM chat_state WHERE chat_id = ?'
    ).get(String(chatId || ''));
    return row ? {
      seq: Number(row.seq) || 0,
      state: JSON.parse(row.payload_json)
    } : null;
  }

  messagesAfter(chatId, afterSeq, limit) {
    return this.messages.messagesAfter(chatId, afterSeq, limit);
  }

  allMessages(chatId, limit) {
    const cap = Math.min(100000, Math.max(1, Number(limit) || 100000));
    return this.db.prepare(`
      SELECT payload_json FROM reliable_messages
      WHERE chat_id = ?
      ORDER BY seq ASC
      LIMIT ?
    `).all(String(chatId || ''), cap).map((row) => JSON.parse(row.payload_json));
  }

  replaceChatMessages(chatId, messages, chatState) {
    const chat = String(chatId || '');
    if (!chat) throw new Error('chatId is required');
    const rows = (Array.isArray(messages) ? messages : []).map((message) =>
      Object.assign({}, message || {})
    );
    const ids = new Set();
    const sequences = new Set();
    for (const message of rows) {
      const id = String(message.id || '');
      const seq = Number(message.seq);
      if (!id || !Number.isSafeInteger(seq) || seq <= 0) {
        throw new Error('replacement messages require id and positive sequence');
      }
      if (ids.has(id)) throw new Error('duplicate replacement message id: ' + id);
      if (sequences.has(seq)) throw new Error('duplicate replacement sequence');
      ids.add(id);
      sequences.add(seq);
    }
    rows.sort((left, right) => Number(left.seq) - Number(right.seq));
    const before = this.writerLease();
    if (!before.ok) return Object.assign({ status: 'fenced' }, before);
    return this.messages.transaction(() => {
      const previous = this.db.prepare(
        'SELECT payload_json FROM chat_state WHERE chat_id = ?'
      ).get(chat);
      const previousState = previous ? JSON.parse(previous.payload_json) : {};
      this.db.prepare('DELETE FROM reliable_messages WHERE chat_id = ?').run(chat);
      const insert = this.db.prepare(`
        INSERT INTO reliable_messages
          (message_id, chat_id, sender_id, client_id, seq, payload_json, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `);
      for (const message of rows) {
        const clientId = String(message.clientId || '').slice(0, 80) || null;
        insert.run(
          String(message.id),
          chat,
          String(message.senderId || 'unknown'),
          clientId,
          Number(message.seq),
          stableJson(message),
          String(message.createdAt || this.messages.now())
        );
      }
      const lastSeq = rows.length
        ? Math.max(...rows.map((message) => Number(message.seq)))
        : 0;
      const updatedAt = this.messages.now();
      if (lastSeq > 0) {
        this.db.prepare(`
          INSERT INTO chat_sequence(chat_id, last_seq, updated_at)
          VALUES (?, ?, ?)
          ON CONFLICT(chat_id) DO UPDATE SET
            last_seq = excluded.last_seq,
            updated_at = excluded.updated_at
        `).run(chat, lastSeq, updatedAt);
      } else {
        this.db.prepare('DELETE FROM chat_sequence WHERE chat_id = ?').run(chat);
      }
      const state = Object.assign({}, previousState, chatState || {}, {
        chatId: chat,
        seq: lastSeq,
        updatedAt
      });
      this.db.prepare(`
        INSERT INTO chat_state(chat_id, seq, payload_json, updated_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(chat_id) DO UPDATE SET
          seq = excluded.seq,
          payload_json = excluded.payload_json,
          updated_at = excluded.updated_at
      `).run(chat, lastSeq, stableJson(state), updatedAt);
      const eventId = this.messages.appendEvent(
        'chat.transcript_replaced',
        chat,
        lastSeq,
        {
          chatId: chat,
          messageIds: rows.map((message) => String(message.id)),
          state
        },
        updatedAt
      );
      this.assertLease(before.epoch);
      return {
        status: 'applied',
        messages: rows.length,
        lastSeq,
        eventId,
        chatState: state
      };
    });
  }

  verify() {
    const failures = [];
    const rows = this.db.prepare(`
      SELECT s.chat_id, s.last_seq,
             COALESCE(MAX(m.seq), 0) AS max_seq,
             COUNT(m.message_id) AS message_count,
             c.seq AS chat_seq
      FROM chat_sequence s
      LEFT JOIN reliable_messages m ON m.chat_id = s.chat_id
      LEFT JOIN chat_state c ON c.chat_id = s.chat_id
      GROUP BY s.chat_id
    `).all();
    for (const row of rows) {
      if (Number(row.last_seq) !== Number(row.max_seq)) {
        failures.push({
          code: 'sequence-mismatch',
          chatId: String(row.chat_id),
          lastSeq: Number(row.last_seq),
          maxSeq: Number(row.max_seq)
        });
      }
      if (Number(row.chat_seq || 0) !== Number(row.last_seq)) {
        failures.push({
          code: 'chat-state-sequence-mismatch',
          chatId: String(row.chat_id),
          sequence: Number(row.last_seq),
          chatSeq: Number(row.chat_seq || 0)
        });
      }
    }
    const orphanMessages = this.db.prepare(`
      SELECT COUNT(*) AS count
      FROM reliable_messages m
      LEFT JOIN chat_sequence s ON s.chat_id = m.chat_id
      WHERE s.chat_id IS NULL OR m.seq > s.last_seq
    `).get();
    if (Number(orphanMessages.count) > 0) {
      failures.push({ code: 'orphan-messages', count: Number(orphanMessages.count) });
    }
    const events = this.db.prepare(
      'SELECT COUNT(*) AS count FROM message_events'
    ).get();
    return {
      ok: failures.length === 0,
      shardId: this.shardId,
      topologyId: this.topologyId,
      chats: rows.length,
      messages: rows.reduce((sum, row) => sum + Number(row.message_count || 0), 0),
      events: Number(events.count) || 0,
      failures
    };
  }

  checkpoint() {
    this.db.exec('PRAGMA wal_checkpoint(TRUNCATE);');
  }

  close() {
    this.messages.close();
  }
}

module.exports = { ShardAuthorityStore };
