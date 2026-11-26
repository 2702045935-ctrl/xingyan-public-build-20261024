'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const {
  VideoRecommendationKernel,
  normalizeEvent
} = require('../lib/video-recommendation');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-video-kernel-'));
const now = '2026-11-20T08:00:00.000Z';

function item(id, overrides) {
  return Object.assign({
    id,
    authorId: 'author-' + id,
    desc: '#AI 测试视频 ' + id,
    music: 'sound-' + id,
    createdAt: now,
    likedBy: [],
    savedBy: [],
    comments: [],
    baseLikes: 0,
    baseComments: 0,
    baseShares: 0
  }, overrides || {});
}

try {
  const file = path.join(root, 'feed-events.json');
  const engine = new VideoRecommendationKernel({
    file,
    now: () => now,
    persistDelayMs: 50,
    maxEventsPerUser: 2000
  });
  const items = [
    item('a', { authorId: 'creator-a', baseLikes: 20 }),
    item('b', { authorId: 'creator-a', baseLikes: 12 }),
    item('c', { authorId: 'creator-b', desc: '#AI 另一个话题', baseLikes: 6 }),
    item('d', { authorId: 'creator-c', desc: '#体育', baseLikes: 3 }),
    item('e', { authorId: 'creator-d', desc: '#AI 探索内容' }),
    item('f', { authorId: 'creator-e', desc: '#体育 新作者' })
  ];
  const itemById = new Map(items.map((row) => [row.id, row]));

  assert.ok(normalizeEvent({ type: 'watch', itemId: 'a', watchMs: 9000 }, Date.parse(now)));
  assert.strictEqual(normalizeEvent({ type: 'unknown', itemId: 'a' }, Date.parse(now)), null);

  const first = engine.recordEvents('viewer', [
    { eventId: 'e1', itemId: 'a', type: 'impression', at: '2026-11-20T07:50:00Z' },
    { eventId: 'e2', itemId: 'a', type: 'play', at: '2026-11-20T07:50:01Z' },
    {
      eventId: 'e3',
      itemId: 'a',
      type: 'watch',
      watchMs: 15000,
      progress: 0.82,
      at: '2026-11-20T07:50:16Z'
    },
    { eventId: 'e4', itemId: 'a', type: 'like', at: '2026-11-20T07:50:17Z' },
    { eventId: 'e5', itemId: 'd', type: 'skip', at: '2026-11-20T07:51:00Z' }
  ], itemById);
  assert.strictEqual(first.accepted, 5);
  const duplicate = engine.recordEvents('viewer', [
    { eventId: 'e4', itemId: 'a', type: 'like' }
  ], itemById);
  assert.strictEqual(duplicate.accepted, 0, 'duplicate event ids must not be counted twice');
  assert.strictEqual(duplicate.duplicates, 1);

  const ranked = engine.rank({
    userId: 'viewer',
    items,
    follows: ['creator-a'],
    friends: ['friend-1'],
    views: { b: { count: 3, lastAt: now } },
    nowMs: Date.parse(now)
  });
  assert.strictEqual(ranked.length, items.length);
  assert.ok(ranked.slice(0, 4).some((row) => row.item.id === 'a'),
    'positive interactions and follow affinity must influence ranking');
  for (let index = 2; index < ranked.length; index += 1) {
    assert.ok(!(ranked[index - 2].item.authorId === ranked[index - 1].item.authorId
      && ranked[index - 1].item.authorId === ranked[index].item.authorId),
      'three consecutive items from one author must be suppressed');
  }
  assert.ok(ranked.every((row) => row.sources.length > 0));

  const fallback = engine.rank({
    userId: 'cold-viewer',
    items,
    follows: [],
    friends: [],
    views: {},
    nowMs: Date.parse(now)
  });
  assert.strictEqual(fallback.length, items.length);
  assert.ok(new Set(fallback.map((row) => row.item.id)).size === items.length);

  engine.flush();
  assert.strictEqual(fs.existsSync(file), true);
  const reopened = new VideoRecommendationKernel({
    file,
    now: () => now,
    persistDelayMs: 50
  });
  assert.strictEqual(reopened.summary('viewer').events, 5);
  assert.strictEqual(reopened.summary('viewer').counts.like, 1);
  reopened.close();

  const loadEngine = new VideoRecommendationKernel({
    file: '',
    now: () => now
  });
  const loadItems = Array.from({ length: 1200 }, (_, index) => item(
    'load-' + index,
    {
      authorId: 'load-author-' + (index % 90),
      music: 'load-sound-' + (index % 60),
      desc: '#AI #topic-' + (index % 35),
      createdAt: new Date(Date.parse(now) - index * 60000).toISOString(),
      baseLikes: index % 30
    }
  ));
  const startedAt = Date.now();
  const loadRanked = loadEngine.rank({
    userId: 'load-viewer',
    items: loadItems,
    follows: ['load-author-1', 'load-author-2'],
    friends: ['friend-load'],
    views: {},
    nowMs: Date.parse(now)
  });
  const elapsed = Date.now() - startedAt;
  assert.strictEqual(loadRanked.length, 300);
  assert.strictEqual(new Set(loadRanked.map((row) => row.item.id)).size, 300);
  assert.ok(elapsed < 1500,
    'ranking 1200 candidates must stay bounded for the request path, elapsed=' + elapsed);

  console.log('video-recommendation: passed');
} finally {
  if (process.platform !== 'win32') {
    fs.rmSync(root, { recursive: true, force: true });
  }
}
