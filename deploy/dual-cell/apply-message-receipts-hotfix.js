'use strict';

const fs = require('fs');
const path = require('path');

const target = path.resolve(process.argv[2] || '');
if (!target || !fs.existsSync(target)) throw new Error('server.js target is missing');

let source = fs.readFileSync(target, 'utf8');
if (source.includes("parts[2] === 'receipts'")) {
  const oldRoute = `      .map((id) => ({
        userId: id,
        deliveredSeq: Math.max(0, Number((db.delivered[id] || {})[chat.id] || 0)),
        readSeq: Math.max(0, Number((db.reads[id] || {})[chat.id] || 0))
      }));`;
  const newRoute = `      .map((id) => {
        const readSeq = Math.max(0, Number((db.reads[id] || {})[chat.id] || 0));
        const deliveredSeq = Math.max(
          readSeq,
          Number((db.delivered[id] || {})[chat.id] || 0)
        );
        return { userId: id, deliveredSeq, readSeq };
      });`;
  if (source.includes(oldRoute)) {
    const backup = target + '.before-receipt-normalize-' + Date.now();
    fs.copyFileSync(target, backup);
    source = source.replace(oldRoute, newRoute);
    const temporary = target + '.receipt-normalize-' + process.pid + '.tmp';
    fs.writeFileSync(temporary, source, 'utf8');
    fs.renameSync(temporary, target);
    console.log('message-receipts-hotfix: normalized backup=' + backup);
  } else {
    console.log('message-receipts-hotfix: already applied');
  }
  process.exit(0);
}

const ackStart = source.indexOf("  if (msg.type === 'ack') {");
const ackEnd = source.indexOf("\n  if (msg.type === 'typing') {", ackStart);
if (ackStart < 0 || ackEnd <= ackStart) throw new Error('ack anchor is missing');

const nextAck = `  if (msg.type === 'ack') {
    const chat = chatById(msg.chatId);
    if (!chat || !chat.memberIds.includes(user.id)) return;
    const seq = Math.max(0, Math.floor(Number(msg.seq) || 0));
    const before = Number((db.delivered[user.id] || {})[chat.id] || 0);
    if (seq > before) {
      setDeliveredSeq(user.id, chat.id, seq);
      sendToChat(chat, {
        type: 'receipt',
        chatId: chat.id,
        userId: user.id,
        deliveredSeq: seq,
        readSeq: Number((db.reads[user.id] || {})[chat.id] || 0)
      }, user.id);
    }
    return;
  }
`;
source = source.slice(0, ackStart) + nextAck + source.slice(ackEnd);

const readNeedle =
  "    sendToChat(chat, { type: 'read', chatId: chat.id, userId: user.id, seq: lastSeq }, user.id);";
const readReplacement = `    setDeliveredSeq(user.id, chat.id, lastSeq);
    sendToChat(chat, { type: 'read', chatId: chat.id, userId: user.id, seq: lastSeq }, user.id);
    sendToChat(chat, {
      type: 'receipt',
      chatId: chat.id,
      userId: user.id,
      deliveredSeq: lastSeq,
      readSeq: lastSeq
    }, user.id);`;
const readCount = source.split(readNeedle).length - 1;
if (readCount !== 2) throw new Error('read anchors changed: expected 2, found ' + readCount);
source = source.split(readNeedle).join(readReplacement);

const messagesAnchor =
  "  if (parts[0] === 'chats' && parts[2] === 'messages' && method === 'GET') {";
if (!source.includes(messagesAnchor)) throw new Error('messages route anchor is missing');
const receiptsRoute = `  if (parts[0] === 'chats' && parts[2] === 'receipts' && method === 'GET') {
    const chat = chatById(parts[1]);
    if (!chat || !chat.memberIds.includes(user.id)) return fail(res, 404, '会话不存在');
    const recipients = chat.memberIds
      .filter((id) => id !== user.id)
      .map((id) => {
        const readSeq = Math.max(0, Number((db.reads[id] || {})[chat.id] || 0));
        const deliveredSeq = Math.max(
          readSeq,
          Number((db.delivered[id] || {})[chat.id] || 0)
        );
        return { userId: id, deliveredSeq, readSeq };
      });
    const deliveredSeq = recipients.length
      ? Math.min(...recipients.map((row) => row.deliveredSeq))
      : 0;
    const readSeq = recipients.length
      ? Math.min(...recipients.map((row) => row.readSeq))
      : 0;
    ok(res, { chatId: chat.id, deliveredSeq, readSeq, recipients });
    return;
  }

`;
source = source.replace(messagesAnchor, receiptsRoute + messagesAnchor);

const stamp = new Date().toISOString().replace(/[-:.]/g, '');
const backup = target + '.before-message-receipts-' + stamp;
fs.copyFileSync(target, backup);
const temporary = target + '.message-receipts-' + process.pid + '.tmp';
fs.writeFileSync(temporary, source, 'utf8');
fs.renameSync(temporary, target);
console.log('message-receipts-hotfix: applied backup=' + backup);
