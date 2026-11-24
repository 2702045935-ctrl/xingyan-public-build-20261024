'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const SCHEMA = 'xingyan.banking.audit.v1';
const LOCK_WAIT_MS = 120;

function atomicJson(file, value) {
  const target = path.resolve(file);
  const temporary = `${target}.${process.pid}.${Date.now()}.tmp`;
  fs.mkdirSync(path.dirname(target), { recursive: true, mode: 0o700 });
  const fd = fs.openSync(temporary, 'w', 0o600);
  try {
    fs.writeFileSync(fd, JSON.stringify(value, null, 2), 'utf8');
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.renameSync(temporary, target);
  try { fs.chmodSync(target, 0o600); } catch (_) { /* Windows ACL */ }
}

function canonical(value) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  const keys = Object.keys(value).sort();
  return `{${keys.map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`;
}

function parseJournal(file, opener) {
  if (!fs.existsSync(file)) return { rows: [], malformed: [] };
  const rows = [];
  const malformed = [];
  fs.readFileSync(file, 'utf8').split('\n').forEach((line, index) => {
    if (!line.trim()) return;
    try {
      const stored = JSON.parse(line);
      rows.push(typeof opener === 'function' ? opener(stored) : stored);
    } catch (_) {
      malformed.push(index + 1);
    }
  });
  return { rows, malformed };
}

class BankingAuditLog {
  constructor(options) {
    const opts = options || {};
    if (!opts.file) throw new Error('banking audit file is required');
    if (!opts.secret) throw new Error('banking audit HMAC secret is required');
    this.file = path.resolve(opts.file);
    this.stateFile = path.resolve(
      opts.stateFile || `${this.file}.state.json`
    );
    this.lockFile = path.resolve(opts.lockFile || `${this.file}.lock`);
    this.secret = String(opts.secret);
    this.seal = typeof opts.seal === 'function' ? opts.seal : null;
    this.open = typeof opts.open === 'function' ? opts.open : null;
    this.now = typeof opts.now === 'function'
      ? opts.now
      : () => new Date().toISOString();
    this.uid = typeof opts.uid === 'function'
      ? opts.uid
      : (prefix) => `${prefix || 'evt'}_${crypto.randomBytes(12).toString('hex')}`;
  }

  hash(record) {
    const copy = Object.assign({}, record);
    delete copy.hash;
    return crypto.createHmac('sha256', this.secret)
      .update(canonical(copy))
      .digest('hex');
  }

  emptyState() {
    return {
      version: 1,
      sequence: 0,
      lastHash: '',
      lastAt: '',
      updatedAt: ''
    };
  }

  readState() {
    try {
      const state = JSON.parse(fs.readFileSync(this.stateFile, 'utf8'));
      if (state && state.version === 1) return state;
    } catch (_) { /* rebuild below */ }
    return this.rebuildState();
  }

  rebuildState() {
    const parsed = parseJournal(this.file, this.open);
    const last = parsed.rows.length ? parsed.rows[parsed.rows.length - 1] : null;
    const state = last
      ? {
        version: 1,
        sequence: Number(last.seq) || parsed.rows.length,
        lastHash: String(last.hash || ''),
        lastAt: String(last.at || ''),
        updatedAt: this.now()
      }
      : this.emptyState();
    atomicJson(this.stateFile, state);
    return state;
  }

  recoverState() {
    const parsed = parseJournal(this.file, this.open);
    const tail = parsed.rows.length ? parsed.rows[parsed.rows.length - 1] : null;
    const state = this.readState();
    if (!tail) return state;
    if (Number(state.sequence) !== Number(tail.seq)
        || String(state.lastHash || '') !== String(tail.hash || '')) {
      return this.rebuildState();
    }
    return state;
  }

  withLock(work) {
    fs.mkdirSync(path.dirname(this.lockFile), { recursive: true, mode: 0o700 });
    const deadline = Date.now() + LOCK_WAIT_MS;
    let fd = null;
    while (fd === null) {
      try {
        fd = fs.openSync(this.lockFile, 'wx', 0o600);
        fs.writeFileSync(fd, JSON.stringify({
          pid: process.pid,
          at: new Date().toISOString()
        }));
        fs.fsyncSync(fd);
      } catch (error) {
        if (!error || error.code !== 'EEXIST') throw error;
        if (Date.now() >= deadline) {
          const stale = this.staleLock();
          if (!stale) throw new Error('banking audit journal is locked');
          try { fs.unlinkSync(this.lockFile); } catch (_) { /* race */ }
        }
      }
    }
    try {
      return work();
    } finally {
      try { fs.closeSync(fd); } catch (_) { /* already closed */ }
      try { fs.unlinkSync(this.lockFile); } catch (_) { /* already gone */ }
    }
  }

  staleLock() {
    try {
      const stat = fs.statSync(this.lockFile);
      return Date.now() - stat.mtimeMs > 30_000;
    } catch (_) {
      return false;
    }
  }

  append(input) {
    const event = input || {};
    return this.withLock(() => {
      const state = this.recoverState();
      const body = {
        schema: SCHEMA,
        seq: Number(state.sequence || 0) + 1,
        id: this.uid('audit'),
        at: this.now(),
        requestId: String(event.requestId || '').slice(0, 160),
        actor: {
          id: String(event.actor && event.actor.id || '').slice(0, 120),
          username: String(event.actor && event.actor.username || '-').slice(0, 160),
          name: String(event.actor && event.actor.name || '-').slice(0, 160),
          role: String(event.actor && event.actor.role || '-').slice(0, 80)
        },
        source: {
          ip: String(event.source && event.source.ip || '').slice(0, 120),
          userAgent: String(event.source && event.source.userAgent || '').slice(0, 500)
        },
        category: String(event.category || 'operation').slice(0, 40),
        severity: String(event.severity || 'normal').slice(0, 40),
        outcome: String(event.outcome || 'success').slice(0, 40),
        action: String(event.action || '').slice(0, 240),
        target: String(event.target || '').slice(0, 500),
        detail: String(event.detail || '').slice(0, 4000),
        context: event.context && typeof event.context === 'object'
          ? event.context
          : {},
        prevHash: String(state.lastHash || '')
      };
      body.hash = this.hash(body);
      fs.mkdirSync(path.dirname(this.file), { recursive: true, mode: 0o700 });
      const stored = this.seal ? this.seal(body) : body;
      const fd = fs.openSync(this.file, 'a', 0o600);
      try {
        fs.writeFileSync(fd, JSON.stringify(stored) + '\n', 'utf8');
        fs.fsyncSync(fd);
      } finally {
        fs.closeSync(fd);
      }
      try { fs.chmodSync(this.file, 0o600); } catch (_) { /* Windows ACL */ }
      atomicJson(this.stateFile, {
        version: 1,
        sequence: body.seq,
        lastHash: body.hash,
        lastAt: body.at,
        updatedAt: this.now()
      });
      return body;
    });
  }

  read(options) {
    const opts = options || {};
    const limit = Math.max(1, Math.min(200_000, Number(opts.limit) || 1000));
    const query = String(opts.q || '').trim().toLowerCase();
    const category = String(opts.category || '').trim().toLowerCase();
    const severity = String(opts.severity || '').trim().toLowerCase();
    const from = Number(opts.from) || 0;
    const to = Number(opts.to) || 0;
    const parsed = parseJournal(this.file, this.open);
    const filtered = parsed.rows.filter((row) => {
      if (category && String(row.category || '').toLowerCase() !== category) return false;
      if (severity && String(row.severity || '').toLowerCase() !== severity) return false;
      const at = Date.parse(String(row.at || ''));
      if (from && at < from) return false;
      if (to && at > to) return false;
      if (!query) return true;
      const hay = [
        row.id,
        row.requestId,
        row.action,
        row.target,
        row.detail,
        row.actor && row.actor.username,
        row.actor && row.actor.name,
        row.actor && row.actor.role,
        row.source && row.source.ip,
        JSON.stringify(row.context || {})
      ].join(' ').toLowerCase();
      return hay.includes(query);
    });
    const rows = filtered.slice(-limit).reverse();
    const days = new Map();
    filtered.forEach((row) => {
      const day = String(row.at || '').slice(0, 10);
      if (day) days.set(day, (days.get(day) || 0) + 1);
    });
    return {
      rows,
      total: filtered.length,
      truncated: filtered.length > limit,
      malformed: parsed.malformed,
      days: Array.from(days, ([day, count]) => ({ day, count }))
        .sort((a, b) => a.day.localeCompare(b.day))
    };
  }

  verify() {
    const parsed = parseJournal(this.file, this.open);
    const failures = parsed.malformed.map((line) => ({
      code: 'malformed-json',
      line
    }));
    let expectedSequence = 1;
    let previous = '';
    parsed.rows.forEach((row, index) => {
      if (!row || row.schema !== SCHEMA) {
        failures.push({ code: 'bad-schema', seq: row && row.seq, line: index + 1 });
        return;
      }
      if (Number(row.seq) !== expectedSequence) {
        failures.push({ code: 'bad-sequence', seq: row.seq, expected: expectedSequence });
      }
      if (String(row.prevHash || '') !== previous) {
        failures.push({ code: 'broken-chain', seq: row.seq });
      }
      if (this.hash(row) !== row.hash) {
        failures.push({ code: 'bad-hmac', seq: row.seq });
      }
      previous = String(row.hash || '');
      expectedSequence = Number(row.seq) + 1;
    });
    const tail = parsed.rows.length ? parsed.rows[parsed.rows.length - 1] : null;
    return {
      ok: failures.length === 0,
      checked: parsed.rows.length,
      failures,
      headSeq: parsed.rows.length ? Number(parsed.rows[0].seq) || 1 : 0,
      tailSeq: tail ? Number(tail.seq) || 0 : 0,
      tailHash: tail ? String(tail.hash || '') : '',
      verifiedAt: this.now()
    };
  }

  export(options) {
    const result = this.read(Object.assign({ limit: 200_000 }, options || {}));
    const rows = result.rows.slice().reverse();
    const manifestBody = {
      schema: 'xingyan.banking.audit.export.v1',
      generatedAt: this.now(),
      count: rows.length,
      firstSeq: rows.length ? Number(rows[0].seq) || 0 : 0,
      lastSeq: rows.length ? Number(rows[rows.length - 1].seq) || 0 : 0,
      tailHash: rows.length ? String(rows[rows.length - 1].hash || '') : '',
      query: {
        q: String(options && options.q || ''),
        category: String(options && options.category || ''),
        severity: String(options && options.severity || ''),
        from: Number(options && options.from) || 0,
        to: Number(options && options.to) || 0
      }
    };
    return {
      manifest: Object.assign({}, manifestBody, {
        manifestMac: crypto.createHmac('sha256', this.secret)
          .update(`export|${canonical(manifestBody)}`)
          .digest('hex')
      }),
      events: rows
    };
  }
}

module.exports = {
  BankingAuditLog,
  SCHEMA,
  canonical
};
