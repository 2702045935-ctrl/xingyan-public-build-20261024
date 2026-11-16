'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const html = fs.readFileSync(
  path.resolve(__dirname, '..', 'public', 'manage.html'),
  'utf8'
);
const scripts = Array.from(html.matchAll(
  /<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g
)).map((match) => match[1]);

assert.ok(scripts.length >= 3);
scripts.forEach((source, index) => {
  assert.doesNotThrow(() => new Function(source), 'script ' + index + ' syntax');
});
assert.ok(html.includes("key: 'shardmaintenance'"));
assert.ok(html.includes('PAGES.shardmaintenance = async () =>'));

console.log('manage-script-syntax: passed (' + scripts.length + ' scripts)');
