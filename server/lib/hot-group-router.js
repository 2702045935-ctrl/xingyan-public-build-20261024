'use strict';

const crypto = require('crypto');

function hash32(value) {
  return crypto.createHash('sha256').update(String(value)).digest().readUInt32BE(0);
}

class HotGroupRouter {
  constructor(options) {
    const opts = options || {};
    this.threshold = Math.max(1, Number(opts.threshold) || 512);
    this.maxBatch = Math.max(1, Number(opts.maxBatch) || 512);
    this.cellCount = Math.max(1, Number(opts.cellCount) || 7);
  }

  classify(chat, activity) {
    const members = Math.max(0, Number(chat && chat.memberIds && chat.memberIds.length) || 0);
    const rate = Math.max(0, Number(activity && activity.messagesPerSecond) || 0);
    if (members >= 10_000 || rate >= 100) return 'dedicated-cell';
    if (members >= this.threshold || rate >= 20) return 'batched-cell';
    return 'local';
  }

  partition(chatId) {
    return hash32(chatId) % this.cellCount;
  }

  plan(input) {
    const row = input || {};
    const chatId = String(row.chatId || '');
    const members = Array.from(new Set((row.memberIds || []).map((value) => String(value))))
      .filter(Boolean);
    const nodes = Array.from(new Set((row.nodeIds || []).map((value) => String(value))))
      .filter(Boolean)
      .sort();
    const mode = this.classify({ memberIds: members }, row.activity);
    if (!chatId) throw new Error('chatId is required');
    if (!nodes.length && mode !== 'local') throw new Error('nodeIds are required for batched fanout');

    const batches = [];
    if (mode === 'local') {
      for (let offset = 0; offset < members.length; offset += this.maxBatch) {
        batches.push({
          nodeId: '',
          cell: -1,
          userIds: members.slice(offset, offset + this.maxBatch)
        });
      }
    } else {
      const byNode = new Map(nodes.map((nodeId) => [nodeId, []]));
      for (const userId of members) {
        const nodeId = nodes[hash32('gateway|' + userId) % nodes.length];
        byNode.get(nodeId).push(userId);
      }
      for (const [nodeId, userIds] of byNode) {
        for (let offset = 0; offset < userIds.length; offset += this.maxBatch) {
          batches.push({
            nodeId,
            cell: this.partition(chatId),
            userIds: userIds.slice(offset, offset + this.maxBatch)
          });
        }
      }
    }
    return {
      chatId,
      mode,
      partition: mode === 'local' ? -1 : this.partition(chatId),
      memberCount: members.length,
      nodeCount: nodes.length,
      maxBatch: this.maxBatch,
      batches
    };
  }
}

module.exports = { HotGroupRouter, hash32 };
