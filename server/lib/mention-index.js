'use strict';

function upperBound(values, target) {
  let low = 0;
  let high = values.length;
  while (low < high) {
    const mid = (low + high) >> 1;
    if (values[mid].seq <= target) low = mid + 1;
    else high = mid;
  }
  return low;
}

function mentionRows(message) {
  const seq = Math.max(0, Number(message && message.seq) || 0);
  if (!message || message.recalled || seq <= 0) return null;
  const senderId = String(message.senderId || '');
  if (!senderId) return null;
  const users = Array.isArray(message.mentions)
    ? Array.from(new Set(message.mentions.map((id) => String(id || '')).filter(Boolean)))
    : [];
  return {
    seq,
    senderId,
    all: message.mentionAll === true,
    users
  };
}

function buildMentionIndex(messages) {
  const index = { all: [], byUser: new Map(), lastSeq: 0 };
  for (const message of (messages || [])) {
    appendMentionIndex(index, message);
  }
  return index;
}

function appendMentionIndex(index, message) {
  if (!index) return;
  const row = mentionRows(message);
  if (!row) return;
  if (row.seq < Number(index.lastSeq || 0)) return;
  if (row.all) {
    index.all.push({ seq: row.seq, senderId: row.senderId });
  }
  for (const userId of row.users) {
    if (!index.byUser.has(userId)) index.byUser.set(userId, []);
    index.byUser.get(userId).push({ seq: row.seq, senderId: row.senderId });
  }
  index.lastSeq = row.seq;
}

function hasUnreadMention(index, userId, lastReadSeq) {
  if (!index || !userId) return false;
  const last = Math.max(0, Number(lastReadSeq) || 0);
  const hasOtherSender = (rows) => {
    for (let i = upperBound(rows || [], last); i < (rows || []).length; i += 1) {
      if (rows[i].senderId !== userId) return true;
    }
    return false;
  };
  if (hasOtherSender(index.all)) return true;
  return hasOtherSender(index.byUser.get(userId));
}

module.exports = {
  appendMentionIndex,
  buildMentionIndex,
  hasUnreadMention
};
