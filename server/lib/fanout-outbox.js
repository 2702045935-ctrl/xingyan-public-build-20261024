'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

function nowIso(now) {
  return new Date(Number(now) || Date.now()).toISOString();
}

function readJsonLines(file) {
  if (!fs.existsSync(file)) return [];
  const rows = [];
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    if (!line.trim()) continue;
    try {
      const row = JSON.parse(line);
      if (row && row.id) rows.push(row);
    } catch (_) { /* preserve forward compatibility after a crash */ }
  }
  return rows;
}

class FanoutOutbox {
  constructor(options) {
    const opts = options || {};
    if (!opts.file) throw new Error('fanout outbox file is required');
    this.file = path.resolve(opts.file);
    this.maxEntries = Math.max(1, Number(opts.maxEntries) || 100_000);
    this.now = typeof opts.now === 'function' ? opts.now : Date.now;
    this.uid = typeof opts.uid === 'function'
      ? opts.uid
      : () => `fanout_${crypto.randomBytes(12).toString('hex')}`;
    this.entries = new Map();
    this.replay();
  }

  replay() {
    this.entries.clear();
    for (const row of readJsonLines(this.file)) {
      if (row.op === 'delete') {
        this.entries.delete(row.id);
        continue;
      }
      if (row.op === 'ack') {
        const current = this.entries.get(row.id);
        if (current) {
          current.status = 'acked';
          current.ackedAt = row.at || nowIso(this.now());
          current.lastError = '';
        }
        continue;
      }
      if (row.op === 'fail') {
        const current = this.entries.get(row.id);
        if (current) {
          current.status = 'pending';
          current.nextAt = Number(row.nextAt) || this.now();
          current.lastError = String(row.error || '');
          current.attempts = Number(row.attempts) || current.attempts || 0;
        }
        continue;
      }
      if (row.op === 'attempt') {
        const current = this.entries.get(row.id);
        if (current) {
          current.status = 'delivering';
          current.attempts = Number(row.attempts) || (current.attempts || 0) + 1;
          current.lastAttemptAt = row.at || nowIso(this.now());
        }
        continue;
      }
      if (row.op === 'enqueue' || row.chatId) {
        this.entries.set(row.id, Object.assign({
          status: 'pending',
          attempts: 0,
          nextAt: this.now()
        }, row));
      }
    }
  }

  append(row) {
    fs.mkdirSync(path.dirname(this.file), { recursive: true, mode: 0o700 });
    const fd = fs.openSync(this.file, 'a', 0o600);
    try {
      fs.writeFileSync(fd, JSON.stringify(row) + '\n', 'utf8');
      fs.fsyncSync(fd);
    } finally {
      fs.closeSync(fd);
    }
  }

  enqueue(input) {
    const row = input || {};
    const publishId = String(row.publishId || row.id || '').trim();
    if (!publishId) throw new Error('publishId is required');
    const existing = Array.from(this.entries.values())
      .find((entry) => entry.publishId === publishId && entry.status !== 'acked');
    if (existing) return { duplicate: true, entry: Object.assign({}, existing) };
    if (this.entries.size >= this.maxEntries) {
      const acked = Array.from(this.entries.values())
        .filter((entry) => entry.status === 'acked')
        .sort((a, b) => String(a.ackedAt || '').localeCompare(String(b.ackedAt || '')))[0];
      if (acked) this.delete(acked.id);
      else throw new Error('fanout outbox is full');
    }
    const entry = {
      id: this.uid('fanout'),
      op: 'enqueue',
      publishId,
      chatId: String(row.chatId || ''),
      payload: row.payload || {},
      nodes: Array.isArray(row.nodes) ? row.nodes : [],
      status: 'pending',
      attempts: 0,
      nextAt: Number(row.nextAt) || this.now(),
      createdAt: nowIso(this.now()),
      lastError: ''
    };
    this.entries.set(entry.id, entry);
    this.append(entry);
    return { duplicate: false, entry: Object.assign({}, entry) };
  }

  attempt(id) {
    const entry = this.entries.get(id);
    if (!entry || entry.status === 'acked') return null;
    entry.status = 'delivering';
    entry.attempts += 1;
    entry.lastAttemptAt = nowIso(this.now());
    this.append({
      id,
      op: 'attempt',
      attempts: entry.attempts,
      at: entry.lastAttemptAt
    });
    return Object.assign({}, entry);
  }

  ack(id) {
    const entry = this.entries.get(id);
    if (!entry) return false;
    entry.status = 'acked';
    entry.ackedAt = nowIso(this.now());
    entry.lastError = '';
    this.append({ id, op: 'ack', at: entry.ackedAt });
    return true;
  }

  fail(id, error, nextAt) {
    const entry = this.entries.get(id);
    if (!entry || entry.status === 'acked') return false;
    entry.status = 'pending';
    entry.nextAt = Number(nextAt) || this.now() + 1000;
    entry.lastError = String(error || '');
    this.append({
      id,
      op: 'fail',
      error: entry.lastError,
      nextAt: entry.nextAt,
      attempts: entry.attempts
    });
    return true;
  }

  delete(id) {
    const entry = this.entries.get(id);
    if (!entry) return false;
    this.entries.delete(id);
    this.append({ id, op: 'delete', at: nowIso(this.now()) });
    return true;
  }

  ready(limit) {
    const at = this.now();
    return Array.from(this.entries.values())
      .filter((entry) => entry.status !== 'acked' && entry.nextAt <= at)
      .sort((a, b) => Number(a.nextAt) - Number(b.nextAt))
      .slice(0, Math.max(1, Number(limit) || 100))
      .map((entry) => Object.assign({}, entry));
  }

  snapshot() {
    const rows = Array.from(this.entries.values());
    return {
      entries: rows.length,
      pending: rows.filter((row) => row.status !== 'acked').length,
      acked: rows.filter((row) => row.status === 'acked').length,
      delivering: rows.filter((row) => row.status === 'delivering').length,
      maxEntries: this.maxEntries,
      file: this.file
    };
  }
}

module.exports = { FanoutOutbox };
