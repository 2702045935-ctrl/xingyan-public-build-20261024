'use strict';

const assert = require('assert');
const { isMediaObjectPath } = require('../lib/media-object-routing');

for (const path of ['/uploads/a.jpg', '/hls/video/index.m3u8', '/api/feed', '/api/feed/like']) {
  assert.strictEqual(isMediaObjectPath('GET', path), true, path);
}
for (const path of ['/api/upload', '/api/upload/raw']) {
  assert.strictEqual(isMediaObjectPath('POST', path), true, path);
  assert.strictEqual(isMediaObjectPath('GET', path), false, path);
}
for (const path of ['/api/chats/c1/messages', '/api/me', '/uploads-missing']) {
  assert.strictEqual(isMediaObjectPath('POST', path), false, path);
}

console.log('media-object-routing: passed');
