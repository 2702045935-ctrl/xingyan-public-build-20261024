#!/usr/bin/env node
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { patchServerSource } = require('../lib/shard-route-server-patch');

function hash(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function replaceOnce(source, from, to, name) {
  if (!source.includes(from)) throw new Error('patch anchor missing: ' + name);
  return source.replace(from, to);
}

function main() {
  const input = path.resolve(process.argv[2] || '');
  const output = path.resolve(process.argv[3] || '');
  if (!input || !output) {
    throw new Error('usage: apply-relation-patch.js INPUT OUTPUT');
  }
  const raw = fs.readFileSync(input);
  const patched = patchServerSource(raw, { expectedSha256: hash(raw) });
  let source = patched.source;
  source = replaceOnce(source,
    'function clearLoginFails(keys) {',
    `/** 关系事件单独带 relation 元数据，客户端据此画 WhatsApp 式系统条。 */
function pushRelationMessage(chat, text, action, actorId, targetId) {
  chat.seq = nextMessageSeq(chat);
  const msg = {
    id: uid('m'), chatId: chat.id, seq: chat.seq, senderId: 'system',
    kind: 'system', content: text,
    relation: { action: String(action || ''), actorId: String(actorId || ''), targetId: String(targetId || '') },
    createdAt: now(), recalled: false
  };
  appendChatMessage(chat, msg);
  (chat.memberIds || []).forEach((id) => {
    sendTo(id, { type: 'message', message: msg, chat: chatSummary(chat, id), clientId: null });
  });
  return msg;
}

function clearLoginFails(keys) {`,
    'relation-helper');
  source = replaceOnce(source,
    "      const c0 = openChatForFriendship(target.id, user.id);\n      sendTo(target.id, { type: 'friend', action: 'accepted', user: publicUser(user) });",
    "      const c0 = openChatForFriendship(target.id, user.id);\n"
      + "      if (c0) pushRelationMessage(c0, '你们已成为好友，现在可以开始聊天了', 'friend_added', target.id, user.id);\n"
      + "      sendTo(target.id, { type: 'friend', action: 'accepted', user: publicUser(user) });",
    'auto-friend-added');
  source = replaceOnce(source,
    "          pushSystemMessage(newChat, '你已添加了' + (fromUser.nickname || fromUser.username)\n"
      + "            + '，现在可以开始聊天了');",
    "          pushRelationMessage(newChat, (fromUser.nickname || fromUser.username || '对方')\n"
      + "            + ' 和 ' + (toUser.nickname || toUser.username || '你')\n"
      + "            + ' 已成为好友，现在可以开始聊天了', 'friend_added', toUser.id, fromUser.id);",
    'verified-friend-added');
  const removeAnchor = "          chatsDirty = true;\n"
    + "          sendTo(user.id, { type: 'chat', action: 'deleted', chatId: chat.id });";
  if (!source.includes(removeAnchor)) throw new Error('patch anchor missing: friend-removed');
  source = source.split(removeAnchor).join(
    "          chatsDirty = true;\n"
      + "          pushRelationMessage(chat, '你们已解除好友关系', 'friend_removed', user.id, target.id);\n"
      + "          sendTo(user.id, { type: 'chat', action: 'deleted', chatId: chat.id });"
  );
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, source, 'utf8');
  console.log(JSON.stringify({ ok: true, sourceSha256: hash(raw), outputSha256: hash(source), output }));
}

main();
