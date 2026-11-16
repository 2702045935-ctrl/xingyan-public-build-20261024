'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const html = fs.readFileSync(
  path.resolve(__dirname, '..', 'public', 'manage.html'),
  'utf8'
);
const maintenanceHtml = fs.readFileSync(
  path.resolve(__dirname, '..', 'public', 'shard-maintenance.html'),
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
const maintenanceScripts = Array.from(maintenanceHtml.matchAll(
  /<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g
)).map((match) => match[1]);
assert.ok(maintenanceScripts.length >= 1);
maintenanceScripts.forEach((source, index) => {
  assert.doesNotThrow(() => new Function(source), 'maintenance script ' + index + ' syntax');
});
assert.ok(maintenanceHtml.includes('/api/ops'));
assert.ok(maintenanceHtml.includes('一次只放行一个分片'));

console.log('manage-script-syntax: passed ('
  + (scripts.length + maintenanceScripts.length) + ' scripts)');
