'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { pathToFileURL } = require('url');
const { DatabaseSync } = require('node:sqlite');
const { canonical, hash } = require('./shard-snapshot');
const { openMessage } = require('./shard-data-inventory');
const { SecurityVault } = require('./security-vault');

const REQUIRED_TABLES = ['reliable_messages', 'chat_sequence', 'reliability_metadata'];

function textCompare(left, right) {
  const a = String(left == null ? '' : left);
  const b = String(right == null ? '' : right);
  return a < b ? -1 : (a > b ? 1 : 0);
}

function finiteInteger(value) {
  const number = Number(value);
  return Number.isSafeInteger(number) ? number : 0;
}

function relativeMessageFile(chatId) {
  return 'messages/' + chatId + '.jsonl';
}

function validBase64(value, expectedLength, allowEmpty) {
  if (typeof value !== 'string') return false;
  if (!value && allowEmpty) return true;
  if (!value || !/^[A-Za-z0-9+/]+={0,2}$/.test(value) || value.length % 4 === 1) {
    return false;
  }
  let bytes;
  try { bytes = Buffer.from(value, 'base64'); }
  catch (_) { return false; }
  if (!allowEmpty && bytes.length === 0) return false;
  return expectedLength == null || bytes.length === expectedLength;
}

function validateEnvelope(envelope) {
  if (!envelope || typeof envelope !== 'object' || Array.isArray(envelope)) {
    return { ok: false, field: 'envelope' };
  }
  if (!validBase64(envelope.iv, 12, false)) return { ok: false, field: 'iv' };
  if (!validBase64(envelope.tag, 16, false)) return { ok: false, field: 'tag' };
  if (!validBase64(envelope.ct, null, false)) return { ok: false, field: 'ct' };
  if (envelope.kv !== undefined
      && (!Number.isSafeInteger(Number(envelope.kv)) || Number(envelope.kv) <= 0)) {
    return { ok: false, field: 'kv' };
  }
  return { ok: true, field: '' };
}

function validateMessageShape(message) {
  return message && typeof message === 'object' && !Array.isArray(message);
}

function createIssueCollector(maxIssues) {
  const cap = Math.max(1, Number(maxIssues) || 20000);
  const issues = [];
  const issueCounts = {};
  let suppressed = 0;
  let warningCount = 0;
  let errorCount = 0;

  const add = (kind, severity, context) => {
    const level = severity === 'warning' ? 'warning' : 'error';
    issueCounts[kind] = (issueCounts[kind] || 0) + 1;
    if (level === 'warning') warningCount += 1;
    else errorCount += 1;
    if (issues.length >= cap) {
      suppressed += 1;
      return;
    }
    const input = context || {};
    const row = {
      kind,
      severity: level,
      chatId: String(input.chatId || ''),
      messageId: String(input.messageId || ''),
      seq: finiteInteger(input.seq),
      line: finiteInteger(input.line),
      file: String(input.file || ''),
      source: String(input.source || ''),
      detail: String(input.detail || ''),
      details: input.details && typeof input.details === 'object'
        ? input.details
        : {}
    };
    issues.push(row);
  };

  return {
    add,
    finish() {
      issues.sort((left, right) =>
        textCompare(left.kind, right.kind)
        || textCompare(left.chatId, right.chatId)
        || textCompare(left.messageId, right.messageId)
        || (left.seq - right.seq)
        || (left.line - right.line)
        || textCompare(left.source, right.source)
        || textCompare(canonical(left.details), canonical(right.details))
      );
      return {
        issues,
        issueCounts: Object.fromEntries(
          Object.entries(issueCounts).sort(([a], [b]) => textCompare(a, b))
        ),
        issueCount: errorCount + warningCount,
        errorCount,
        warningCount,
        suppressedIssues: suppressed
      };
    }
  };
}

async function scanMessageFile(options) {
  const opts = options || {};
  const chatId = String(opts.chatId || '');
  const file = String(opts.file || '');
  const relativeFile = relativeMessageFile(chatId);
  const addIssue = opts.addIssue;
  const messagesById = opts.messagesById;
  const clientOwners = opts.clientOwners;
  const state = {
    chatId,
    file: relativeFile,
    filePresent: true,
    fileSize: 0,
    lineCount: 0,
    messageCount: 0,
    invalidLineCount: 0,
    firstSeq: 0,
    lastSeq: 0,
    uniqueSeqCount: 0,
    missingSeqCount: 0,
    duplicateSeqCount: 0,
    orderViolationCount: 0,
    fileHash: ''
  };
  const sequenceOwners = new Map();
  const fileHasher = crypto.createHash('sha256');
  let previousSeq = 0;

  try { state.fileSize = fs.statSync(file).size; }
  catch (_) {
    state.filePresent = false;
    addIssue('message-file-stat', 'error', {
      chatId,
      file: relativeFile,
      detail: 'message file cannot be read'
    });
    return state;
  }

  const input = fs.createReadStream(file, { encoding: 'utf8' });
  const lines = readline.createInterface({
    input,
    crlfDelay: Infinity,
    terminal: false
  });

  try {
    for await (const rawLine of lines) {
      state.lineCount += 1;
      const lineNumber = state.lineCount;
      const line = String(rawLine || '').trim();
      fileHasher.update(String(lineNumber));
      fileHasher.update('\0');
      fileHasher.update(line);
      fileHasher.update('\n');
      if (!line) continue;

      let stored;
      try { stored = JSON.parse(line); }
      catch (_) {
        state.invalidLineCount += 1;
        addIssue('message-invalid-json', 'error', {
          chatId,
          line: lineNumber,
          file: relativeFile,
          detail: 'line is not valid JSON'
        });
        continue;
      }

      if (stored && typeof stored === 'object' && stored.e === 1) {
        const envelope = validateEnvelope(stored);
        if (!envelope.ok) {
          state.invalidLineCount += 1;
          addIssue('message-invalid-envelope', 'error', {
            chatId,
            line: lineNumber,
            file: relativeFile,
            detail: 'invalid encrypted envelope',
            details: { field: envelope.field }
          });
          continue;
        }
      }

      let message;
      try {
        message = openMessage(opts.secret || '', chatId, line, opts.vault || null);
      } catch (_) {
        state.invalidLineCount += 1;
        addIssue('message-decrypt', 'error', {
          chatId,
          line: lineNumber,
          file: relativeFile,
          detail: opts.secretAvailable
            ? 'message could not be decrypted'
            : 'message requires unavailable encryption material'
        });
        continue;
      }

      if (!validateMessageShape(message)) {
        state.invalidLineCount += 1;
        addIssue('message-invalid-shape', 'error', {
          chatId,
          line: lineNumber,
          file: relativeFile,
          detail: 'message is not an object'
        });
        continue;
      }
      state.messageCount += 1;

      const messageId = String(message.id || '');
      const payloadChatId = String(message.chatId || '');
      const senderId = String(message.senderId || '');
      const clientId = String(message.clientId || '').slice(0, 80);
      const seq = finiteInteger(message.seq);

      if (!messageId) {
        addIssue('message-id-missing', 'error', {
          chatId,
          line: lineNumber,
          file: relativeFile,
          detail: 'message has no stable id'
        });
      }
      if (!payloadChatId) {
        addIssue('message-chat-id-missing', 'error', {
          chatId,
          messageId,
          line: lineNumber,
          file: relativeFile,
          detail: 'message has no chat id'
        });
      } else if (payloadChatId !== chatId) {
        addIssue('message-chat-id-mismatch', 'error', {
          chatId,
          messageId,
          line: lineNumber,
          file: relativeFile,
          detail: 'message chat id differs from its message file',
          details: { payloadChatId }
        });
      }
      if (seq <= 0) {
        addIssue('message-seq-invalid', 'error', {
          chatId,
          messageId,
          line: lineNumber,
          file: relativeFile,
          detail: 'message seq must be a positive safe integer'
        });
      }
      if (!senderId) {
        addIssue('message-sender-missing', 'error', {
          chatId,
          messageId,
          line: lineNumber,
          file: relativeFile,
          detail: 'message has no sender id'
        });
      }
      if (opts.requireClientId && !clientId
          && senderId !== 'system' && message.kind !== 'system') {
        addIssue('client-id-missing', 'warning', {
          chatId,
          messageId,
          line: lineNumber,
          file: relativeFile,
          detail: 'outgoing message has no stable client id'
        });
      }

      if (seq > 0) {
        const owner = sequenceOwners.get(seq);
        if (owner) {
          state.duplicateSeqCount += 1;
          addIssue('message-seq-duplicate', 'error', {
            chatId,
            messageId,
            seq,
            line: lineNumber,
            file: relativeFile,
            detail: 'seq is used by more than one message',
            details: { firstMessageId: owner }
          });
        } else {
          sequenceOwners.set(seq, messageId);
        }
        if (previousSeq > 0 && seq < previousSeq) {
          state.orderViolationCount += 1;
          addIssue('message-seq-order', 'error', {
            chatId,
            messageId,
            seq,
            line: lineNumber,
            file: relativeFile,
            detail: 'seq decreases in file order',
            details: { previousSeq }
          });
        }
        previousSeq = seq;
        if (!state.firstSeq || seq < state.firstSeq) state.firstSeq = seq;
        if (seq > state.lastSeq) state.lastSeq = seq;
        state.uniqueSeqCount = sequenceOwners.size;
      }

      if (messageId) {
        const existing = messagesById.get(messageId);
        if (existing) {
          if (existing.chatId === chatId) {
            addIssue('message-id-duplicate', 'error', {
              chatId,
              messageId,
              seq,
              line: lineNumber,
              file: relativeFile,
              detail: 'message id appears more than once',
              details: { firstLine: existing.line }
            });
          } else {
            addIssue('message-id-cross-chat', 'error', {
              chatId,
              messageId,
              seq,
              line: lineNumber,
              file: relativeFile,
              detail: 'message id is already assigned to another chat',
              details: { firstChatId: existing.chatId }
            });
          }
        } else {
          messagesById.set(messageId, {
            chatId,
            messageId,
            seq,
            senderId,
            clientId,
            line: lineNumber,
            file: relativeFile,
            payloadHash: hash(message),
            message
          });
        }
      }

      if (clientId) {
        const key = chatId + '\u0000' + senderId + '\u0000' + clientId;
        const owner = clientOwners.get(key);
        if (owner && owner.messageId !== messageId) {
          addIssue('client-id-duplicate', 'error', {
            chatId,
            messageId,
            seq,
            line: lineNumber,
            file: relativeFile,
            detail: 'client id is reused by another message',
            details: {
              senderId,
              clientId,
              firstMessageId: owner.messageId
            }
          });
        } else if (!owner) {
          clientOwners.set(key, { messageId, seq, chatId, senderId, clientId });
        }
      }

    }
  } catch (_) {
    state.invalidLineCount += 1;
    addIssue('message-file-read', 'error', {
      chatId,
      file: relativeFile,
      detail: 'message file could not be read to completion'
    });
  } finally {
    lines.close();
    input.destroy();
  }

  state.missingSeqCount = state.lastSeq > 0
    ? Math.max(0, state.lastSeq - state.uniqueSeqCount)
    : 0;
  state.fileHash = fileHasher.digest('hex');
  if (state.missingSeqCount > 0) {
    addIssue('message-seq-gap', 'error', {
      chatId,
      file: relativeFile,
      detail: 'conversation sequence has gaps',
      details: {
        firstSeq: state.firstSeq,
        lastSeq: state.lastSeq,
        missingSeqCount: state.missingSeqCount
      }
    });
  }
  return state;
}

function readReliabilityDatabase(options) {
  const opts = options || {};
  const databaseFile = String(opts.databaseFile || '');
  const addIssue = opts.addIssue;
  const messages = new Map();
  const byChat = new Map();
  const sequences = new Map();
  const metadata = {};
  const result = {
    present: false,
    schemaComplete: false,
    tables: [],
    missingTables: [],
    rowCount: 0,
    chatCount: 0,
    messages,
    byChat,
    sequences,
    metadata
  };

  if (!databaseFile || !fs.existsSync(databaseFile)) return result;
  result.present = true;

  const walFile = databaseFile + '-wal';
  const journalFile = databaseFile + '-journal';
  if ((fs.existsSync(walFile) && fs.statSync(walFile).size > 0)
      || (fs.existsSync(journalFile) && fs.statSync(journalFile).size > 0)) {
    addIssue('reliability-database-not-checkpointed', 'error', {
      file: path.basename(databaseFile),
      detail: 'database has uncheckpointed sidecar data; audit a checkpointed snapshot'
    });
    result.schemaComplete = false;
    return result;
  }

  let db;
  try {
    /*
     * immutable=1 prevents SQLite from creating -wal/-shm files beside the
     * source. A non-empty WAL is rejected above because immutable mode does
     * not replay it.
     */
    db = new DatabaseSync(pathToFileURL(databaseFile).href + '?immutable=1', {
      readOnly: true
    });
  } catch (_) {
    addIssue('reliability-database-open', 'error', {
      file: path.basename(databaseFile),
      detail: 'reliability database cannot be opened read-only'
    });
    return result;
  }

  try {
    let tableRows;
    try {
      tableRows = db.prepare(`
        SELECT name FROM sqlite_master
        WHERE type = 'table'
        ORDER BY name
      `).all();
    } catch (_) {
      addIssue('reliability-database-schema', 'error', {
        file: path.basename(databaseFile),
        detail: 'reliability database schema cannot be read'
      });
      return result;
    }
    result.tables = tableRows.map((row) => String(row.name || ''));
    const tableSet = new Set(result.tables);
    result.missingTables = REQUIRED_TABLES.filter((name) => !tableSet.has(name));
    result.schemaComplete = result.missingTables.length === 0;
    if (!result.schemaComplete) {
      addIssue('reliability-table-missing', 'error', {
        file: path.basename(databaseFile),
        detail: 'reliability database is missing required tables',
        details: { tables: result.missingTables }
      });
    }

    if (tableSet.has('reliability_metadata')) {
      const rows = db.prepare(`
        SELECT key, value FROM reliability_metadata ORDER BY key
      `).all();
      for (const row of rows) {
        metadata[String(row.key || '')] = String(row.value || '');
      }
      const marker = String(metadata['legacy-backfill-v1'] || '');
      if (marker) {
        try { result.legacyBackfill = JSON.parse(marker); }
        catch (_) {
          addIssue('reliability-metadata-invalid', 'error', {
            file: path.basename(databaseFile),
            source: 'legacy-backfill-v1',
            detail: 'backfill marker is not valid JSON'
          });
        }
      }
    }

    if (!tableSet.has('reliable_messages')) return result;

    const statement = db.prepare(`
      SELECT message_id, chat_id, sender_id, client_id, seq,
             payload_json, created_at
      FROM reliable_messages
      ORDER BY chat_id, seq, message_id
    `);
    for (const row of statement.iterate()) {
      result.rowCount += 1;
      const messageId = String(row.message_id || '');
      const chatId = String(row.chat_id || '');
      const senderId = String(row.sender_id || '');
      const clientId = String(row.client_id || '');
      const seq = finiteInteger(row.seq);
      let payload = null;
      let payloadError = false;
      try { payload = JSON.parse(String(row.payload_json || '')); }
      catch (_) {
        payloadError = true;
        addIssue('reliability-payload-json', 'error', {
          chatId,
          messageId,
          seq,
          source: 'reliability',
          detail: 'reliability payload is not valid JSON'
        });
      }

      if (!messageId) {
        addIssue('reliability-id-missing', 'error', {
          chatId,
          seq,
          source: 'reliability',
          detail: 'reliability row has no message id'
        });
      }
      if (!chatId) {
        addIssue('reliability-chat-id-missing', 'error', {
          messageId,
          seq,
          source: 'reliability',
          detail: 'reliability row has no chat id'
        });
      }
      if (seq <= 0) {
        addIssue('reliability-seq-invalid', 'error', {
          chatId,
          messageId,
          source: 'reliability',
          detail: 'reliability seq must be a positive safe integer'
        });
      }
      if (!senderId) {
        addIssue('reliability-sender-missing', 'error', {
          chatId,
          messageId,
          seq,
          source: 'reliability',
          detail: 'reliability row has no sender id'
        });
      }
      if (payload && validateMessageShape(payload)) {
        if (String(payload.id || '') !== messageId) {
          addIssue('reliability-payload-id-mismatch', 'error', {
            chatId,
            messageId,
            seq,
            source: 'reliability',
            detail: 'payload id differs from reliability message id',
            details: { payloadId: String(payload.id || '') }
          });
        }
        if (String(payload.chatId || '') !== chatId) {
          addIssue('reliability-payload-chat-mismatch', 'error', {
            chatId,
            messageId,
            seq,
            source: 'reliability',
            detail: 'payload chat id differs from reliability chat id',
            details: { payloadChatId: String(payload.chatId || '') }
          });
        }
        if (finiteInteger(payload.seq) !== seq) {
          addIssue('reliability-payload-seq-mismatch', 'error', {
            chatId,
            messageId,
            seq,
            source: 'reliability',
            detail: 'payload seq differs from reliability seq',
            details: { payloadSeq: finiteInteger(payload.seq) }
          });
        }
      }

      if (messageId) {
        const duplicate = messages.get(messageId);
        if (duplicate) {
          addIssue('reliability-id-duplicate', 'error', {
            chatId,
            messageId,
            seq,
            source: 'reliability',
            detail: 'reliability message id appears more than once'
          });
        } else {
          messages.set(messageId, {
            chatId,
            messageId,
            seq,
            senderId,
            clientId,
            payload,
            payloadHash: payload && !payloadError ? hash(payload) : '',
            payloadError
          });
        }
      }

      const chat = byChat.get(chatId) || {
        chatId,
        messageCount: 0,
        firstSeq: 0,
        lastSeq: 0,
        uniqueSeqCount: 0,
        missingSeqCount: 0,
        sequenceOwners: new Map()
      };
      chat.messageCount += 1;
      if (seq > 0) {
        if (!chat.sequenceOwners.has(seq)) chat.sequenceOwners.set(seq, messageId);
        else {
          addIssue('reliability-seq-duplicate', 'error', {
            chatId,
            messageId,
            seq,
            source: 'reliability',
            detail: 'reliability seq is used by more than one message'
          });
        }
        if (!chat.firstSeq || seq < chat.firstSeq) chat.firstSeq = seq;
        if (seq > chat.lastSeq) chat.lastSeq = seq;
        chat.uniqueSeqCount = chat.sequenceOwners.size;
      }
      byChat.set(chatId, chat);
    }
    result.chatCount = byChat.size;
    for (const chat of byChat.values()) {
      chat.missingSeqCount = chat.lastSeq > 0
        ? Math.max(0, chat.lastSeq - chat.uniqueSeqCount)
        : 0;
      if (chat.missingSeqCount > 0) {
        addIssue('reliability-seq-gap', 'error', {
          chatId: chat.chatId,
          source: 'reliability',
          detail: 'reliability sequence has gaps',
          details: {
            firstSeq: chat.firstSeq,
            lastSeq: chat.lastSeq,
            missingSeqCount: chat.missingSeqCount
          }
        });
      }
    }

    if (tableSet.has('chat_sequence')) {
      const rows = db.prepare(`
        SELECT chat_id, last_seq, updated_at
        FROM chat_sequence
        ORDER BY chat_id
      `).all();
      for (const row of rows) {
        const chatId = String(row.chat_id || '');
        const lastSeq = finiteInteger(row.last_seq);
        if (!chatId || lastSeq < 0) {
          addIssue('chat-sequence-invalid', 'error', {
            chatId,
            seq: lastSeq,
            source: 'reliability',
            detail: 'chat sequence row is invalid'
          });
        }
        if (chatId) {
          sequences.set(chatId, {
            chatId,
            lastSeq,
            updatedAt: String(row.updated_at || '')
          });
        }
      }
    }
  } catch (_) {
    addIssue('reliability-database-read', 'error', {
      file: path.basename(databaseFile),
      detail: 'reliability database could not be read completely'
    });
  } finally {
    try { db.close(); } catch (_) { /* preserve audit result */ }
  }

  return result;
}

function compareMessageStores(fileState, reliability, addIssue) {
  if (!reliability.present || !reliability.schemaComplete) return;

  for (const message of fileState.messagesById.values()) {
    const stored = reliability.messages.get(message.messageId);
    if (!stored) {
      addIssue('reliability-message-missing', 'error', {
        chatId: message.chatId,
        messageId: message.messageId,
        seq: message.seq,
        file: message.file,
        line: message.line,
        source: 'comparison',
        detail: 'message file row is missing from reliability storage'
      });
      continue;
    }
    if (stored.chatId !== message.chatId) {
      addIssue('reliability-message-chat-mismatch', 'error', {
        chatId: message.chatId,
        messageId: message.messageId,
        seq: message.seq,
        file: message.file,
        line: message.line,
        source: 'comparison',
        detail: 'message belongs to another chat in reliability storage',
        details: { reliabilityChatId: stored.chatId }
      });
    }
    if (stored.seq !== message.seq) {
      addIssue('reliability-message-seq-mismatch', 'error', {
        chatId: message.chatId,
        messageId: message.messageId,
        seq: message.seq,
        file: message.file,
        line: message.line,
        source: 'comparison',
        detail: 'message seq differs in reliability storage',
        details: { reliabilitySeq: stored.seq }
      });
    }
    if (stored.senderId !== message.senderId) {
      addIssue('reliability-message-sender-mismatch', 'error', {
        chatId: message.chatId,
        messageId: message.messageId,
        seq: message.seq,
        file: message.file,
        line: message.line,
        source: 'comparison',
        detail: 'message sender differs in reliability storage',
        details: { reliabilitySenderId: stored.senderId }
      });
    }
    if (stored.clientId !== message.clientId) {
      addIssue('reliability-message-client-mismatch', 'error', {
        chatId: message.chatId,
        messageId: message.messageId,
        seq: message.seq,
        file: message.file,
        line: message.line,
        source: 'comparison',
        detail: 'message client id differs in reliability storage',
        details: {
          reliabilityClientId: stored.clientId,
          fileClientId: message.clientId
        }
      });
    }
    if (!stored.payloadError && stored.payloadHash
        && stored.payloadHash !== message.payloadHash) {
      addIssue('reliability-message-payload-mismatch', 'error', {
        chatId: message.chatId,
        messageId: message.messageId,
        seq: message.seq,
        file: message.file,
        line: message.line,
        source: 'comparison',
        detail: 'message payload differs from reliability storage'
      });
    }
  }

  for (const stored of reliability.messages.values()) {
    if (!fileState.messagesById.has(stored.messageId)) {
      addIssue('message-file-row-missing', 'error', {
        chatId: stored.chatId,
        messageId: stored.messageId,
        seq: stored.seq,
        file: relativeMessageFile(stored.chatId),
        source: 'comparison',
        detail: 'reliability row is missing from the message file'
      });
    }
  }
}

function compareSequences(fileChats, reliability, addIssue) {
  if (!reliability.present || !reliability.schemaComplete) return;
  const chatIds = new Set([
    ...fileChats.keys(),
    ...reliability.byChat.keys(),
    ...reliability.sequences.keys()
  ]);
  for (const chatId of Array.from(chatIds).sort(textCompare)) {
    const file = fileChats.get(chatId);
    const database = reliability.byChat.get(chatId);
    const sequence = reliability.sequences.get(chatId);
    const fileMax = file ? file.lastSeq : 0;
    const databaseMax = database ? database.lastSeq : 0;
    const observedMax = Math.max(fileMax, databaseMax);

    if (!sequence && observedMax > 0) {
      addIssue('chat-sequence-missing', 'error', {
        chatId,
        source: 'reliability',
        detail: 'conversation has messages but no chat sequence row'
      });
      continue;
    }
    if (!sequence) continue;
    if (observedMax > 0 && sequence.lastSeq !== observedMax) {
      addIssue('last-seq-mismatch', 'error', {
        chatId,
        seq: sequence.lastSeq,
        source: 'reliability',
        detail: 'chat sequence does not match the durable maximum',
        details: {
          fileMax,
          reliabilityMax: databaseMax,
          observedMax
        }
      });
    }
    if (file && file.filePresent && sequence.lastSeq !== file.lastSeq) {
      addIssue('last-seq-file-mismatch', 'error', {
        chatId,
        seq: sequence.lastSeq,
        source: 'comparison',
        detail: 'chat sequence differs from the message file maximum',
        details: { fileMax }
      });
    }
    if (database && sequence.lastSeq !== database.lastSeq) {
      addIssue('last-seq-reliability-mismatch', 'error', {
        chatId,
        seq: sequence.lastSeq,
        source: 'comparison',
        detail: 'chat sequence differs from reliability message maximum',
        details: { reliabilityMax: databaseMax }
      });
    }
    if (observedMax === 0 && sequence.lastSeq > 0) {
      addIssue('chat-sequence-orphan', 'warning', {
        chatId,
        seq: sequence.lastSeq,
        source: 'reliability',
        detail: 'chat sequence exists without durable messages'
      });
    }
  }
}

async function auditMessageConsistency(options) {
  const opts = options || {};
  const dataDir = path.resolve(String(opts.dataDir || ''));
  if (!dataDir) throw new Error('dataDir is required');
  const databaseFile = opts.databaseFile
    ? path.resolve(String(opts.databaseFile))
    : path.join(dataDir, 'message-reliability.sqlite3');
  const secret = String(opts.secret || '');
  const secretAvailable = !!secret;
  const collector = createIssueCollector(opts.maxIssues);
  const addIssue = collector.add;
  let vault = null;
  if (secret && fs.existsSync(path.join(dataDir, 'keyring.json'))) {
    try {
      vault = new SecurityVault({ dataDir, rootMaterial: secret });
    } catch (_) {
      vault = null;
    }
  }

  const messagesDir = path.join(dataDir, 'messages');
  let names = [];
  try {
    names = fs.readdirSync(messagesDir)
      .filter((name) => name.endsWith('.jsonl'))
      .sort(textCompare);
  } catch (_) {
    names = [];
  }

  const messagesById = new Map();
  const clientOwners = new Map();
  const fileChats = new Map();
  for (const name of names) {
    const chatId = name.slice(0, -'.jsonl'.length);
    const file = path.join(messagesDir, name);
    const state = await scanMessageFile({
      chatId,
      file,
      secret,
      secretAvailable,
      vault,
      requireClientId: opts.requireClientId === true,
      addIssue,
      messagesById,
      clientOwners
    });
    state.messagesById = messagesById;
    fileChats.set(chatId, state);
  }

  const reliability = readReliabilityDatabase({ databaseFile, addIssue });
  const fileState = { messagesById };
  compareMessageStores(fileState, reliability, addIssue);
  compareSequences(fileChats, reliability, addIssue);

  const counts = {
    messageFiles: fileChats.size,
    messageLines: Array.from(fileChats.values())
      .reduce((sum, chat) => sum + chat.lineCount, 0),
    messages: Array.from(fileChats.values())
      .reduce((sum, chat) => sum + chat.messageCount, 0),
    reliabilityMessages: reliability.rowCount,
    reliabilityChats: reliability.chatCount
  };
  const chatSummaries = Array.from(fileChats.values())
    .map((chat) => {
      const database = reliability.byChat.get(chat.chatId) || null;
      return {
        chatId: chat.chatId,
        file: chat.file,
        fileMessages: chat.messageCount,
        fileLines: chat.lineCount,
        fileInvalidLines: chat.invalidLineCount,
        fileFirstSeq: chat.firstSeq,
        fileLastSeq: chat.lastSeq,
        fileMissingSeqCount: chat.missingSeqCount,
        fileDuplicateSeqCount: chat.duplicateSeqCount,
        fileOrderViolationCount: chat.orderViolationCount,
        fileHash: chat.fileHash,
        reliabilityMessages: database ? database.messageCount : 0,
        reliabilityFirstSeq: database ? database.firstSeq : 0,
        reliabilityLastSeq: database ? database.lastSeq : 0,
        reliabilityMissingSeqCount: database ? database.missingSeqCount : 0,
        lastSeq: reliability.sequences.has(chat.chatId)
          ? reliability.sequences.get(chat.chatId).lastSeq
          : null
      };
    })
    .sort((left, right) => textCompare(left.chatId, right.chatId));

  for (const chatId of Array.from(reliability.byChat.keys()).sort(textCompare)) {
    if (fileChats.has(chatId)) continue;
    const database = reliability.byChat.get(chatId);
    chatSummaries.push({
      chatId,
      file: '',
      fileMessages: 0,
      fileLines: 0,
      fileInvalidLines: 0,
      fileFirstSeq: 0,
      fileLastSeq: 0,
      fileMissingSeqCount: 0,
      fileDuplicateSeqCount: 0,
      fileOrderViolationCount: 0,
      fileHash: '',
      reliabilityMessages: database.messageCount,
      reliabilityFirstSeq: database.firstSeq,
      reliabilityLastSeq: database.lastSeq,
      reliabilityMissingSeqCount: database.missingSeqCount,
      lastSeq: reliability.sequences.has(chatId)
        ? reliability.sequences.get(chatId).lastSeq
        : null
    });
  }
  chatSummaries.sort((left, right) => textCompare(left.chatId, right.chatId));

  const issueSummary = collector.finish();
  const source = String(opts.sourceId || '');
  const deterministic = {
    version: 1,
    audit: 'message-consistency',
    sourceId: source,
    dataDirName: path.basename(dataDir),
    databaseName: path.basename(databaseFile),
    secretAvailable,
    counts,
    reliability: {
      present: reliability.present,
      schemaComplete: reliability.schemaComplete,
      tables: reliability.tables,
      missingTables: reliability.missingTables,
      legacyBackfill: reliability.legacyBackfill || null
    },
    chats: chatSummaries,
    issues: issueSummary.issues,
    issueCounts: issueSummary.issueCounts,
    issueCount: issueSummary.issueCount,
    errorCount: issueSummary.errorCount,
    warningCount: issueSummary.warningCount,
    suppressedIssues: issueSummary.suppressedIssues
  };
  return Object.assign({
    generatedAt: new Date().toISOString(),
    readOnly: true,
    ok: issueSummary.errorCount === 0
  }, deterministic, {
    fingerprint: hash(deterministic)
  });
}

module.exports = {
  auditMessageConsistency,
  validateEnvelope
};
