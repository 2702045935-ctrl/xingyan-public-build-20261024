'use strict';

const fs = require('fs');
const path = require('path');

const EVENT_TYPES = new Set([
  'impression',
  'play',
  'first_frame',
  'watch',
  'complete',
  'skip',
  'like',
  'unlike',
  'comment',
  'share',
  'favorite',
  'unfavorite',
  'follow',
  'unfollow',
  'profile_open',
  'sound_open',
  'playback_error',
  'not_interested'
]);

const POSITIVE_WEIGHTS = {
  complete: 4.8,
  like: 7.2,
  comment: 5.2,
  share: 8.4,
  favorite: 6.4,
  follow: 9.0,
  profile_open: 2.8,
  sound_open: 2.2
};

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function hash32(value) {
  let hash = 2166136261;
  const text = String(value || '');
  for (let index = 0; index < text.length; index += 1) {
    hash ^= text.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function tagsOf(item) {
  const out = new Set();
  const configured = String(item && item.tag || '').trim();
  if (configured) out.add(configured.toLowerCase());
  const matches = String(item && item.desc || '').match(/#[^\s#]{1,24}/g) || [];
  for (const value of matches) out.add(value.slice(1).toLowerCase());
  return Array.from(out);
}

function toMillis(value, fallback) {
  const parsed = Date.parse(String(value || ''));
  return Number.isFinite(parsed) ? parsed : fallback;
}

function normalizeEvent(input, nowMs) {
  const row = input || {};
  const type = String(row.type || '').trim().toLowerCase();
  const itemId = String(row.itemId || row.id || '').trim().slice(0, 80);
  if (!EVENT_TYPES.has(type) || !itemId) return null;
  const atMs = clamp(toMillis(row.at, nowMs), nowMs - 30 * 86400000, nowMs + 60000);
  const watchMs = clamp(Number(row.watchMs || row.watchTimeMs || 0) || 0, 0, 6 * 3600000);
  const durationMs = clamp(Number(row.durationMs || 0) || 0, 0, 6 * 3600000);
  const progress = clamp(Number(row.progress || 0) || 0, 0, 1);
  return {
    id: String(row.eventId || row.id || '').trim().slice(0, 120),
    itemId,
    type,
    at: new Date(atMs).toISOString(),
    watchMs: Math.round(watchMs),
    durationMs: Math.round(durationMs),
    progress,
    completed: row.completed === true || type === 'complete',
    source: String(row.source || '').trim().slice(0, 40)
  };
}

function eventValue(event) {
  if (event.type === 'skip') return -4.2;
  if (event.type === 'unlike') return -5.0;
  if (event.type === 'unfollow') return -6.0;
  if (event.type === 'not_interested') return -12.0;
  if (event.type === 'impression') return -0.06;
  if (event.type === 'play') return 0.7;
  if (event.type === 'watch') {
    const seconds = event.watchMs / 1000;
    const completion = event.progress;
    return clamp(seconds / 18 + completion * 2.2, -0.5, 4.2);
  }
  return POSITIVE_WEIGHTS[event.type] || 0;
}

class VideoRecommendationKernel {
  constructor(options) {
    const opts = options || {};
    this.file = String(opts.file || '');
    this.now = typeof opts.now === 'function'
      ? opts.now
      : () => new Date().toISOString();
    this.persistDelayMs = clamp(Number(opts.persistDelayMs) || 1500, 50, 60000);
    this.maxEventsPerUser = clamp(Number(opts.maxEventsPerUser) || 5000, 100, 20000);
    this.data = { version: 1, users: {} };
    this.timer = null;
    this.load();
  }

  load() {
    if (!this.file || !fs.existsSync(this.file)) return;
    try {
      const parsed = JSON.parse(fs.readFileSync(this.file, 'utf8'));
      if (parsed && parsed.version === 1 && parsed.users && typeof parsed.users === 'object') {
        this.data = parsed;
      }
    } catch (_) {
      this.data = { version: 1, users: {} };
    }
  }

  userState(userId) {
    const id = String(userId || '');
    if (!this.data.users[id]) this.data.users[id] = { events: [], updatedAt: '' };
    if (!Array.isArray(this.data.users[id].events)) this.data.users[id].events = [];
    return this.data.users[id];
  }

  recordEvents(userId, events, itemById) {
    const state = this.userState(userId);
    const nowMs = Date.parse(this.now());
    const known = new Set(state.events.map((event) => event.id).filter(Boolean));
    let accepted = 0;
    let rejected = 0;
    let duplicates = 0;
    const rows = Array.isArray(events) ? events.slice(0, 100) : [];
    for (const input of rows) {
      const event = normalizeEvent(input, Number.isFinite(nowMs) ? nowMs : Date.now());
      if (!event || rejected >= 100) {
        rejected += 1;
        continue;
      }
      if (event.id && known.has(event.id)) {
        duplicates += 1;
        continue;
      }
      if (!itemById || !itemById.has(event.itemId)) {
        rejected += 1;
        continue;
      }
      if (event.id) known.add(event.id);
      state.events.push(event);
      accepted += 1;
    }
    if (state.events.length > this.maxEventsPerUser) {
      state.events.splice(0, state.events.length - this.maxEventsPerUser);
    }
    state.updatedAt = this.now();
    if (accepted) this.schedulePersist();
    return { accepted, rejected, duplicates };
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

  preferenceModel(userId, itemById, nowMs) {
    const state = this.userState(userId);
    const author = new Map();
    const tag = new Map();
    const music = new Map();
    const bump = (map, key, value) => {
      if (!key) return;
      map.set(key, (map.get(key) || 0) + value);
    };
    for (const event of state.events.slice(-2500)) {
      const item = itemById.get(event.itemId);
      if (!item) continue;
      const ageDays = Math.max(0, nowMs - toMillis(event.at, nowMs)) / 86400000;
      const decay = Math.exp(-ageDays / 21);
      const value = eventValue(event) * decay;
      bump(author, String(item.authorId || ''), value);
      bump(music, String(item.music || '').trim().toLowerCase(), value * 0.55);
      for (const valueTag of tagsOf(item)) bump(tag, valueTag, value * 0.7);
    }
    return { author, tag, music };
  }

  itemFeedback(userId, itemById, nowMs) {
    const state = this.userState(userId);
    const out = new Map();
    for (const event of state.events.slice(-3500)) {
      const item = itemById.get(event.itemId);
      if (!item) continue;
      let stat = out.get(event.itemId);
      if (!stat) {
        stat = {
          exposure: 0,
          plays: 0,
          completes: 0,
          skips: 0,
          likes: 0,
          shares: 0,
          negatives: 0,
          watchMs: 0,
          progress: 0,
          lastAt: 0
        };
        out.set(event.itemId, stat);
      }
      const atMs = toMillis(event.at, nowMs);
      stat.lastAt = Math.max(stat.lastAt, atMs);
      if (event.type === 'impression') stat.exposure += 1;
      if (event.type === 'play') stat.plays += 1;
      if (event.type === 'complete') stat.completes += 1;
      if (event.type === 'skip') stat.skips += 1;
      if (event.type === 'like') stat.likes += 1;
      if (event.type === 'unlike') stat.likes -= 1;
      if (event.type === 'share') stat.shares += 1;
      if (event.type === 'not_interested') stat.negatives += 1;
      if (event.type === 'not_interested' || event.type === 'unfollow') stat.negatives += 0.5;
      if (event.type === 'watch') {
        stat.watchMs += event.watchMs;
        stat.progress = Math.max(stat.progress, event.progress);
      }
    }
    return out;
  }

  localQuality(stat) {
    if (!stat) return 0;
    const plays = stat.plays + stat.exposure * 0.25;
    const completionRate = (stat.completes + 0.9) / (plays + 8);
    const likeRate = (Math.max(0, stat.likes) + 0.7) / (plays + 20);
    const shareRate = (stat.shares + 0.2) / (plays + 30);
    const skipRate = (stat.skips + 2.5) / (plays + 10);
    const negativeRate = (stat.negatives + 0.2) / (plays + 15);
    return completionRate * 0.42
      + likeRate * 2.0
      + shareRate * 2.8
      + stat.progress * 0.18
      + (1 - clamp(skipRate, 0, 1)) * 0.08
      - negativeRate * 2.2;
  }

  rank(input) {
    const value = input || {};
    const userId = String(value.userId || '');
    const items = Array.isArray(value.items) ? value.items : [];
    const nowMs = Number.isFinite(value.nowMs) ? Number(value.nowMs) : Date.now();
    const follows = new Set(value.follows || []);
    const friends = new Set(value.friends || []);
    const views = value.views && typeof value.views === 'object' ? value.views : {};
    const itemById = new Map(items.map((item) => [String(item.id), item]));
    const prefs = this.preferenceModel(userId, itemById, nowMs);
    const feedback = this.itemFeedback(userId, itemById, nowMs);
    const hasProfile = prefs.author.size > 0 || prefs.tag.size > 0 || prefs.music.size > 0;
    const today = new Date(nowMs).toISOString().slice(0, 10);

    const scored = items.map((item) => {
      const itemId = String(item.id);
      const likes = (Array.isArray(item.likedBy) ? item.likedBy.length : 0)
        + (Number(item.baseLikes) || 0);
      const comments = (Array.isArray(item.comments) ? item.comments.length : 0)
        + (Number(item.baseComments) || 0);
      const shares = Number(item.baseShares) || 0;
      const favorites = Array.isArray(item.savedBy) ? item.savedBy.length : 0;
      const globalQuality = 1 + Math.log1p(likes + comments * 2 + shares * 3 + favorites * 2);
      const createdAt = toMillis(item.createdAt, nowMs - 86400000);
      const ageHours = Math.max(0.1, (nowMs - createdAt) / 3600000);
      const fresh = 1 / Math.pow(ageHours + 2, 0.38);
      const coldStart = ageHours <= 24 ? 1.42 : (ageHours <= 72 ? 1.14 : 1);

      let affinity = 0;
      affinity += clamp(prefs.author.get(String(item.authorId || '')) || 0, -20, 20) * 0.16;
      affinity += clamp(prefs.music.get(String(item.music || '').trim().toLowerCase()) || 0, -12, 12) * 0.08;
      for (const tag of tagsOf(item)) {
        affinity += clamp(prefs.tag.get(tag) || 0, -14, 14) * 0.1;
      }
      affinity = Math.exp(clamp(affinity, -2.2, 1.7));

      const friendLikes = (Array.isArray(item.likedBy) ? item.likedBy : [])
        .filter((id) => friends.has(id)).length;
      const followed = follows.has(String(item.authorId || ''));
      const social = 1 + Math.min(1.7, friendLikes * 0.72) + (followed ? 1.15 : 0);

      const stat = feedback.get(itemId);
      const local = this.localQuality(stat);
      const seen = Math.max(
        Number(views[itemId] && views[itemId].count || views[itemId]) || 0,
        stat ? stat.exposure : 0
      );
      const fatigue = seen > 0 ? 1 / (1 + seen * 1.15) : 1;
      const negativeCount = stat ? stat.negatives : 0;
      const negative = negativeCount > 0 ? 0.08 : 1;
      const explorationSeed = hash32(userId + '|' + itemId + '|' + today) / 0xffffffff;
      const exploration = hasProfile
        ? 0.985 + explorationSeed * 0.03
        : 0.94 + explorationSeed * 0.12;

      const sources = [];
      if (affinity > 1.08) sources.push('interest');
      if (followed) sources.push('follow');
      if (friendLikes > 0) sources.push('social');
      if (likes + comments + shares + favorites > 0) sources.push('trending');
      if (ageHours <= 48) sources.push('fresh');
      if (explorationSeed > 0.82) sources.push('explore');
      if (!sources.length) sources.push('platform');

      const score = Math.max(0, globalQuality)
        * fresh
        * coldStart
        * affinity
        * social
        * (1 + clamp(local, -1, 2.5))
        * fatigue
        * negative
        * exploration;
      return {
        item,
        score,
        sources,
        components: {
          globalQuality,
          fresh,
          coldStart,
          affinity,
          social,
          local,
          fatigue,
          negative,
          exploration
        }
      };
    });

    scored.sort((left, right) => right.score - left.score);
    const out = [];
    const authorWindow = [];
    const tagWindow = [];
    const musicWindow = [];
    const remaining = scored.slice();
    while (remaining.length) {
      let pickedIndex = -1;
      for (let index = 0; index < remaining.length; index += 1) {
        const row = remaining[index];
        const item = row.item;
        const author = String(item.authorId || item.id);
        const music = String(item.music || '').trim().toLowerCase();
        const tags = tagsOf(item);
        const authorRepeated = authorWindow.filter((id) => id === author).length >= 2;
        const musicRepeated = music && musicWindow.filter((id) => id === music).length >= 2;
        const tagRepeated = tags.some((tag) =>
          tagWindow.filter((id) => id === tag).length >= 3
        );
        if (authorRepeated || musicRepeated || tagRepeated) continue;
        if (out.length > 0 && authorWindow[authorWindow.length - 1] === author) continue;
        pickedIndex = index;
        break;
      }
      if (pickedIndex < 0) {
        for (let index = 0; index < remaining.length; index += 1) {
          const author = String(remaining[index].item.authorId || remaining[index].item.id);
          if (out.length === 0 || authorWindow[authorWindow.length - 1] !== author) {
            pickedIndex = index;
            break;
          }
        }
        if (pickedIndex < 0) pickedIndex = 0;
      }
      const row = remaining.splice(pickedIndex, 1)[0];
      out.push(row);
      const author = String(row.item.authorId || row.item.id);
      const music = String(row.item.music || '').trim().toLowerCase();
      authorWindow.push(author);
      musicWindow.push(music);
      for (const tag of tagsOf(row.item)) tagWindow.push(tag);
      if (authorWindow.length > 8) authorWindow.shift();
      if (musicWindow.length > 10) musicWindow.shift();
      if (tagWindow.length > 18) tagWindow.splice(0, tagWindow.length - 18);
    }

    // Put one exploration candidate into every six-item window when available.
    const used = new Set(out.map((row) => String(row.item.id)));
    const explorePool = scored.filter((row) =>
      row.sources.includes('explore') && !used.has(String(row.item.id))
    );
    if (explorePool.length) {
      for (let index = 5; index < out.length && explorePool.length; index += 6) {
        const candidate = explorePool.shift();
        if (!candidate || used.has(String(candidate.item.id))) continue;
        out.splice(index, 0, candidate);
        used.add(String(candidate.item.id));
      }
    }
    return out.slice(0, 300);
  }

  summary(userId) {
    const state = this.userState(userId);
    const counts = {};
    for (const event of state.events) {
      counts[event.type] = (counts[event.type] || 0) + 1;
    }
    return {
      version: 1,
      events: state.events.length,
      updatedAt: state.updatedAt || '',
      counts
    };
  }
}

module.exports = {
  EVENT_TYPES,
  VideoRecommendationKernel,
  hash32,
  normalizeEvent,
  tagsOf
};
