'use strict';

const assert = require('assert');
const {
  appendMentionIndex,
  buildMentionIndex,
  hasUnreadMention
} = require('../lib/mention-index');

const messages = [{
  seq: 1,
  senderId: 'alice',
  kind: 'text',
  content: '@bob old mention',
  mentions: ['bob'],
  recalled: false
}];
for (let seq = 2; seq <= 61; seq += 1) {
  messages.push({
    seq,
    senderId: 'alice',
    kind: 'text',
    content: 'ordinary ' + seq,
    recalled: false
  });
}
messages.push({
  seq: 62,
  senderId: 'bob',
  kind: 'text',
  content: '@所有人 self mention',
  mentionAll: true,
  recalled: false
});
messages.push({
  seq: 63,
  senderId: 'carol',
  kind: 'text',
  content: '@bob recalled',
  mentions: ['bob'],
  recalled: true
});

const index = buildMentionIndex(messages);
assert.strictEqual(hasUnreadMention(index, 'bob', 0), true,
  'a mention must stay pending even after more than forty newer messages');
assert.strictEqual(hasUnreadMention(index, 'bob', 1), false,
  'reading past the mention must clear the pending mention');
assert.strictEqual(hasUnreadMention(index, 'bob', 62), false,
  'the sender must not see their own @all as someone mentioning them');
assert.strictEqual(hasUnreadMention(buildMentionIndex([messages[63]]), 'bob', 0), false,
  'recalled messages must not create mentions');

appendMentionIndex(index, {
  seq: 64,
  senderId: 'dave',
  kind: 'text',
  content: '@bob new',
  mentions: ['bob'],
  recalled: false
});
assert.strictEqual(hasUnreadMention(index, 'bob', 63), true,
  'incremental appends must update an existing mention index');

console.log('mention-index: passed');
