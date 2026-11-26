'use strict';

const fs = require('fs');
const path = require('path');

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function normalize(value) {
  return String(value || '')
    .normalize('NFKC')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}

function queryTokens(value) {
  return normalize(value).split(' ').filter(Boolean).slice(0, 8);
}

function fieldScore(query, fields) {
  const q = normalize(query);
  if (!q) return 0;
  const tokens = queryTokens(q);
  let best = 0;
  for (const raw of fields || []) {
    const text = normalize(raw);
    if (!text) continue;
    if (text === q) best = Math.max(best, 150);
    else if (text.startsWith(q)) best = Math.max(best, 120);
    else if (text.includes(q)) best = Math.max(best, 92);
    else if (tokens.length > 1 && tokens.every((token) => text.includes(token))) {
      best = Math.max(best, 70);
    }
  }
  return best;
}

function recencyScore(value, nowMs) {
  const at = Date.parse(String(value || ''));
  if (!Number.isFinite(at)) return 0;
  const ageHours = Math.max(0, nowMs - at) / 3600000;
  return 18 * Math.exp(-ageHours / 168);
}

class SearchRankingKernel {
  constructor(options) {
    const opts = options || {};
    this.file = String(opts.file || '');
    this.persistDelayMs = clamp(Number(opts.persistDelayMs) || 1500, 100, 30000);
    this.maxEventsPerUser = clamp(Number(opts.maxEventsPerUser) || 3000, 100, 10000);
    this.data = { version: 1, users: {} };
    this.timer = null;
    this.load();
  }

  load() {
    if (!this.file || !fs.existsSync(this.file)) return;
    try {
      const value = JSON.parse(fs.readFileSync(this.file, 'utf8'));
      if (value && value.version === 1 && value.users && typeof value.users === 'object') {
        this.data = value;
      }
    } catch (_) {
      this.data = { version: 1, users: {} };
    }
  }

  userState(userId) {
    const id = String(userId || '');
    if (!this.data.users[id]) {
      this.data.users[id] = { events: [], updatedAt: '' };
    }
    if (!Array.isArray(this.data.users[id].events)) {
      this.data.users[id].events = [];
    }
    return this.data.users[id];
  }

  recordEvents(userId, events) {
    const state = this.userState(userId);
    const known = new Set(state.events.map((event) => event.eventId).filter(Boolean));
    let accepted = 0;
    let duplicates = 0;
    let rejected = 0;
    for (const input of Array.isArray(events) ? events.slice(0, 100) : []) {
      const row = input || {};
      const type = String(row.type || '').trim().toLowerCase();
      if (!['query', 'click', 'open', 'skip', 'impression'].includes(type)) {
        rejected += 1;
        continue;
      }
      const eventId = String(row.eventId || '').trim().slice(0, 120);
      if (eventId && known.has(eventId)) {
        duplicates += 1;
        continue;
      }
      const atMs = Date.parse(String(row.at || ''));
      const event = {
        eventId,
        type,
        scope: String(row.scope || 'all').trim().slice(0, 20),
        targetId: String(row.targetId || '').trim().slice(0, 100),
        query: normalize(row.query).slice(0, 80),
        at: new Date(Number.isFinite(atMs) ? atMs : Date.now()).toISOString()
      };
      state.events.push(event);
      if (eventId) known.add(eventId);
      accepted += 1;
    }
    if (state.events.length > this.maxEventsPerUser) {
      state.events.splice(0, state.events.length - this.maxEventsPerUser);
    }
    state.updatedAt = new Date().toISOString();
    if (accepted) this.schedulePersist();
    return { accepted, duplicates, rejected };
  }

  profile(userId, nowMs) {
    const now = Number.isFinite(nowMs) ? nowMs : Date.now();
    const scopes = new Map();
    const targets = new Map();
    const queries = new Map();
    for (const event of this.userState(userId).events.slice(-1800)) {
      const at = Date.parse(event.at);
      const ageDays = Number.isFinite(at) ? Math.max(0, now - at) / 86400000 : 30;
      const decay = Math.exp(-ageDays / 30);
      const value = event.type === 'click' || event.type === 'open'
        ? 3.5
        : event.type === 'skip' ? -2.2
          : event.type === 'query' ? 0.35
            : -0.03;
      scopes.set(event.scope, (scopes.get(event.scope) || 0) + value * decay);
      if (event.targetId) {
        const key = event.scope + ':' + event.targetId;
        targets.set(key, (targets.get(key) || 0) + value * decay);
        const cross = '*:' + event.targetId;
        targets.set(cross, (targets.get(cross) || 0) + value * decay * 0.65);
      }
      if (event.type === 'query' && event.query) {
        queries.set(event.query, (queries.get(event.query) || 0) + decay);
      }
    }
    return { scopes, targets, queries };
  }

  rank(userId, scope, rows, query, options) {
    const opts = options || {};
    const fields = typeof opts.fields === 'function' ? opts.fields : () => [];
    const idOf = typeof opts.idOf === 'function' ? opts.idOf : ((row) => row.id);
    const recencyOf = typeof opts.recencyOf === 'function'
      ? opts.recencyOf
      : ((row) => row.at || row.createdAt);
    const limit = clamp(Number(opts.limit) || 30, 1, 100);
    const now = Date.now();
    const profile = this.profile(userId, now);
    const seen = new Set();
    const scored = [];
    for (const row of Array.isArray(rows) ? rows : []) {
      const id = String(idOf(row) || '');
      if (!id || seen.has(id)) continue;
      seen.add(id);
      const match = fieldScore(query, fields(row));
      if (match <= 0) continue;
      const personal = clamp(profile.targets.get(scope + ':' + id) || 0, -20, 20);
      const crossScope = clamp(profile.targets.get('*:' + id) || 0, -20, 20);
      const scopeAffinity = clamp(profile.scopes.get(scope) || 0, -8, 8);
      scored.push({
        row,
        score: match + recencyScore(recencyOf(row), now)
          + personal * 1.8 + crossScope * 0.7 + scopeAffinity
      });
    }
    scored.sort((a, b) => b.score - a.score);
    return {
      rows: scored.slice(0, limit).map((item) => item.row),
      total: scored.length,
      profile
    };
  }

  suggestions(userId, hotWords, limit) {
    const profile = this.profile(userId, Date.now());
    const recent = Array.from(profile.queries.entries())
      .sort((a, b) => b[1] - a[1])
      .map((entry) => entry[0]);
    const seen = new Set();
    return recent
      .concat(Array.isArray(hotWords) ? hotWords : [])
      .filter((word) => {
        const key = normalize(word);
        if (!key || seen.has(key)) return false;
        seen.add(key);
        return true;
      })
      .slice(0, clamp(Number(limit) || 12, 1, 30));
  }

  schedulePersist() {
    if (this.timer || !this.file) return;
    this.timer = setTimeout(() => {
      this.timer = null;
      this.flush();
    }, this.persistDelayMs);
    if (this.timer.unref) this.timer.unref();
  }

  flush() {
    if (!this.file) return false;
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    const temp = this.file + '.tmp-' + process.pid;
    fs.writeFileSync(temp, JSON.stringify(this.data), 'utf8');
    fs.renameSync(temp, this.file);
    return true;
  }

  close() {
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = null;
    }
    this.flush();
  }
}

module.exports = {
  SearchRankingKernel,
  normalize,
  queryTokens,
  fieldScore,
  recencyScore
};
