'use strict';


const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const KEYRING_FILE = 'keyring.json';
const AUDIT_FILE = 'security-audit.jsonl';
const WRAP_ALGO = 'aes-256-gcm';

function atomicJson(file, value, mode = 0o600) {
  const temp = `${file}.${process.pid}.${Date.now()}.tmp`;
  const fd = fs.openSync(temp, 'w', mode);
  try {
    fs.writeFileSync(fd, JSON.stringify(value, null, 2));
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.renameSync(temp, file);
  try { fs.chmodSync(file, mode); } catch (error) { }
}

class SecurityVault {
  constructor(options) {
    const opts = options || {};
    this.dataDir = path.resolve(opts.dataDir);
    this.keyringPath = path.join(this.dataDir, KEYRING_FILE);
    this.auditPath = path.join(this.dataDir, AUDIT_FILE);
    this.rootMaterial = String(opts.rootMaterial || '');
    if (!this.rootMaterial) throw new Error('security vault root material is empty');
    const explicitHex = String(opts.rootKeyHex || '');
    this.rootKey = /^[a-f0-9]{64}$/i.test(explicitHex)
      ? Buffer.from(explicitHex, 'hex')
      : crypto.createHmac('sha256', this.rootMaterial).update('chris:vault:wrap:v1').digest();
    this.keyring = null;
    this.dataKeyCache = new Map();
  }

  ensure() {
    if (this.keyring) return this.keyring;
    fs.mkdirSync(this.dataDir, { recursive: true, mode: 0o700 });
    try {
      this.keyring = JSON.parse(fs.readFileSync(this.keyringPath, 'utf8'));
    } catch (error) {
      this.keyring = {
        version: 1,
        createdAt: new Date().toISOString(),
        provider: 'local-envelope-aes-256-gcm',
        purposes: {}
      };
    }
    if (!this.keyring.purposes || typeof this.keyring.purposes !== 'object') {
      this.keyring.purposes = {};
    }
    this.ensurePurpose('message');
    this.save();
    return this.keyring;
  }

  save() {
    this.ensureOnly();
    atomicJson(this.keyringPath, this.keyring);
  }

  ensureOnly() {
    if (!this.keyring) {
      try {
        this.keyring = JSON.parse(fs.readFileSync(this.keyringPath, 'utf8'));
      } catch (error) {
        throw new Error('keyring is not initialized');
      }
    }
  }

  wrapAad(purpose, version) {
    return Buffer.from(`chris-keyring:${purpose}:${version}`, 'utf8');
  }

  wrapDataKey(purpose, version, raw) {
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv(WRAP_ALGO, this.rootKey, iv);
    cipher.setAAD(this.wrapAad(purpose, version));
    const ciphertext = Buffer.concat([cipher.update(raw), cipher.final()]);
    return {
      iv: iv.toString('base64'),
      tag: cipher.getAuthTag().toString('base64'),
      ct: ciphertext.toString('base64')
    };
  }

  unwrapDataKey(purpose, version) {
    const cacheKey = `${purpose}:${version}`;
    const cached = this.dataKeyCache.get(cacheKey);
    if (cached) return cached;
    const item = this.keyring.purposes[purpose] && this.keyring.purposes[purpose].keys[String(version)];
    if (!item) throw new Error(`missing ${purpose} key version ${version}`);
    const decipher = crypto.createDecipheriv(
      WRAP_ALGO,
      this.rootKey,
      Buffer.from(item.iv, 'base64')
    );
    decipher.setAAD(this.wrapAad(purpose, version));
    decipher.setAuthTag(Buffer.from(item.tag, 'base64'));
    const raw = Buffer.concat([
      decipher.update(Buffer.from(item.ct, 'base64')),
      decipher.final()
    ]);
    this.dataKeyCache.set(cacheKey, raw);
    return raw;
  }

  ensurePurpose(purpose) {
    this.ensureOnly();
    let entry = this.keyring.purposes[purpose];
    if (entry && entry.keys && entry.active) return entry;
    const raw = crypto.randomBytes(32);
    entry = {
      active: 1,
      createdAt: new Date().toISOString(),
      keys: {
        '1': Object.assign({
          createdAt: new Date().toISOString(),
          retiredAt: ''
        }, this.wrapDataKey(purpose, 1, raw))
      }
    };
    this.keyring.purposes[purpose] = entry;
    this.dataKeyCache.set(`${purpose}:1`, raw);
    return entry;
  }

  activeVersion(purpose) {
    return Number(this.ensurePurpose(purpose).active);
  }

  dataKey(purpose, version) {
    this.ensurePurpose(purpose);
    return this.unwrapDataKey(purpose, Number(version));
  }

  scopedKey(purpose, scope, version) {
    return crypto.createHmac('sha256', this.dataKey(purpose, version))
      .update(String(scope))
      .digest();
  }

  sealJson(purpose, scope, value) {
    const version = this.activeVersion(purpose);
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv(WRAP_ALGO, this.scopedKey(purpose, scope, version), iv);
    const ciphertext = Buffer.concat([
      cipher.update(Buffer.from(JSON.stringify(value), 'utf8')),
      cipher.final()
    ]);
    return {
      e: 1,
      kv: version,
      iv: iv.toString('base64'),
      tag: cipher.getAuthTag().toString('base64'),
      ct: ciphertext.toString('base64')
    };
  }

  openJson(purpose, scope, envelope, legacyKey) {
    const item = envelope || {};
    const key = item.kv
      ? this.scopedKey(purpose, scope, Number(item.kv))
      : legacyKey;
    if (!key) throw new Error('no decryption key available');
    const decipher = crypto.createDecipheriv(WRAP_ALGO, key, Buffer.from(item.iv, 'base64'));
    decipher.setAuthTag(Buffer.from(item.tag, 'base64'));
    const plain = Buffer.concat([
      decipher.update(Buffer.from(item.ct, 'base64')),
      decipher.final()
    ]);
    return JSON.parse(plain.toString('utf8'));
  }

  rotate(purpose, actor, reason) {
    const entry = this.ensurePurpose(purpose);
    const versions = Object.keys(entry.keys || {}).map(Number).filter(Number.isFinite);
    const next = Math.max(0, ...versions) + 1;
    const raw = crypto.randomBytes(32);
    entry.keys[String(next)] = Object.assign({
      createdAt: new Date().toISOString(),
      retiredAt: ''
    }, this.wrapDataKey(purpose, next, raw));
    entry.active = next;
    entry.rotatedAt = new Date().toISOString();
    this.dataKeyCache.set(`${purpose}:${next}`, raw);
    this.save();
    this.appendAudit('key.rotate', actor || 'system', {
      purpose,
      version: next,
      reason: String(reason || '')
    });
    return { purpose, active: next };
  }

  status() {
    this.ensure();
    const purposes = {};
    for (const [purpose, entry] of Object.entries(this.keyring.purposes)) {
      const versions = Object.keys(entry.keys || {}).map(Number).filter(Number.isFinite).sort((a, b) => a - b);
      purposes[purpose] = {
        active: entry.active,
        versions,
        fingerprint: crypto.createHash('sha256')
          .update(this.dataKey(purpose, entry.active))
          .digest('hex')
          .slice(0, 16)
      };
    }
    return {
      provider: this.keyring.provider,
      createdAt: this.keyring.createdAt,
      purposes
    };
  }

  previousAuditHash() {
    try {
      const lines = fs.readFileSync(this.auditPath, 'utf8').trim().split('\n').filter(Boolean);
      if (!lines.length) return '';
      const last = JSON.parse(lines[lines.length - 1]);
      return String(last.hash || '');
    } catch (error) {
      return '';
    }
  }

  appendAudit(action, actor, details) {
    const record = {
      at: new Date().toISOString(),
      action: String(action || ''),
      actor: String(actor || ''),
      details: details && typeof details === 'object' ? details : {},
      prevHash: this.previousAuditHash()
    };
    record.hash = crypto.createHash('sha256')
      .update(JSON.stringify(record))
      .digest('hex');
    fs.mkdirSync(path.dirname(this.auditPath), { recursive: true, mode: 0o700 });
    fs.appendFileSync(this.auditPath, JSON.stringify(record) + '\n', { encoding: 'utf8', mode: 0o600 });
    try { fs.chmodSync(this.auditPath, 0o600); } catch (error) { }
    return record;
  }

  auditTail(limit) {
    const n = Math.max(1, Math.min(1000, Number(limit) || 100));
    try {
      return fs.readFileSync(this.auditPath, 'utf8').trim().split('\n').filter(Boolean)
        .slice(-n)
        .reverse()
        .map((line) => JSON.parse(line));
    } catch (error) {
      return [];
    }
  }

  verifyAudit() {
    try {
      const rows = fs.readFileSync(this.auditPath, 'utf8').trim().split('\n').filter(Boolean);
      let previous = '';
      for (let index = 0; index < rows.length; index += 1) {
        const record = JSON.parse(rows[index]);
        const expected = crypto.createHash('sha256')
          .update(JSON.stringify(Object.assign({}, record, { hash: undefined })))
          .digest('hex');
        if (record.prevHash !== previous || record.hash !== expected) {
          return { ok: false, brokenAt: index + 1, rows: rows.length };
        }
        previous = record.hash;
      }
      return { ok: true, rows: rows.length };
    } catch (error) {
      return { ok: false, brokenAt: 0, error: error.message };
    }
  }
}

function createSecurityVault(options) {
  const vault = new SecurityVault(options);
  vault.ensure();
  return vault;
}

module.exports = { createSecurityVault, SecurityVault };
