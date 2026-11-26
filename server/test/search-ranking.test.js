'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const {
  SearchRankingKernel,
  fieldScore,
  normalize
} = require('../lib/search-ranking');

function main() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-search-rank-'));
  const file = path.join(dir, 'events.json');
  const kernel = new SearchRankingKernel({ file, persistDelayMs: 100 });
  assert.strictEqual(normalize('  Ｈｅｌｌｏ   WORLD  '), 'hello world');
  assert.ok(fieldScore('alice chen', ['Alice Chen'])
    > fieldScore('alice', ['Alice Chen']));
  assert.ok(fieldScore('project', ['design', 'project alpha']) > 0);

  kernel.recordEvents('u1', [{
    eventId: 'click-project',
    type: 'click',
    scope: 'groups',
    targetId: 'g-project',
    query: 'project',
    at: new Date().toISOString()
  }]);
  const groups = [
    { id: 'g-other', name: 'Project general', at: '2026-11-20T00:00:00Z' },
    { id: 'g-project', name: 'Project alpha', at: '2026-11-20T00:00:00Z' },
    { id: 'g-project', name: 'Project duplicate', at: '2026-11-20T00:00:00Z' }
  ];
  const ranked = kernel.rank('u1', 'groups', groups, 'project', {
    fields: (row) => [row.name],
    idOf: (row) => row.id,
    recencyOf: (row) => row.at,
    limit: 10
  });
  assert.strictEqual(ranked.total, 2, 'duplicate result ids must collapse');
  assert.strictEqual(ranked.rows[0].id, 'g-project',
    'personalized click affinity must outrank a newer unmatched result');

  const suggestions = kernel.suggestions(
    'u1',
    ['朋友圈', 'project', '视频号'],
    10
  );
  assert.strictEqual(new Set(suggestions).size, suggestions.length);
  assert.ok(suggestions.includes('project'));
  kernel.close();

  try {
    fs.rmSync(dir, { recursive: true, force: true });
  } catch (_) {
    /* Windows may still hold the file briefly. */
  }
  console.log('search-ranking: passed');
}

main();
