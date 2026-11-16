'use strict';

const crypto = require('crypto');
const { canonical, hash } = require('./shard-snapshot');
const { resolveRoute } = require('./shard-route-plan');
const { routingKey, stableShard } = require('./shard-runtime');
const { pairKey } = require('./shard-domain');

function ownerFor(routePlan, shardCount, entityType, entityId) {
  if (entityType === 'user' || entityType === 'chat') {
    return resolveRoute(routePlan, entityType, entityId);
  }
  const routeId = routingKey(entityType, entityId);
  return stableShard(entityType + ':' + routeId, shardCount);
}

function buildPlacementPlan(options) {
  const opts = options || {};
  const data = opts.data || {};
  const routePlan = opts.routePlan;
  const shardCount = Math.floor(Number(routePlan && routePlan.shardCount));
  if (!Number.isInteger(shardCount) || shardCount < 2) {
    throw new Error('route plan shardCount is invalid');
  }
  const failures = [];
  const rows = [];
  const seen = new Set();

  function add(entityType, physicalId, routeEntityType, routeEntityId, source) {
    const physical = String(physicalId || '');
    const routed = String(routeEntityId || '');
    if (!physical || !routed) {
      failures.push({ code: 'missing-id', entityType, source });
      return;
    }
    const unique = entityType + ':' + physical;
    if (seen.has(unique)) {
      failures.push({ code: 'duplicate-plan-item', entityType, id: physical, source });
      return;
    }
    seen.add(unique);
    const owner = ownerFor(routePlan, shardCount, routeEntityType || entityType, routed);
    if (!Number.isInteger(owner) || owner < 0 || owner >= shardCount) {
      failures.push({ code: 'invalid-owner', entityType, id: physical, owner, source });
      return;
    }
    rows.push({ entityType, id: physical, owner, source });
  }

  for (const user of data.users || []) {
    add('user', user && user.id, 'user', user && user.id, 'users.json');
  }
  for (const friendship of data.friendships || []) {
    const routeId = friendship && friendship.fromId && friendship.toId
      ? pairKey(friendship.fromId, friendship.toId)
      : '';
    add('friendship', friendship && friendship.id, 'friendship', routeId, 'friendships.json');
  }
  for (const chat of data.chats || []) {
    add('chat', chat && chat.id, 'chat', chat && chat.id, 'chats.json');
  }
  for (const [ownerId, chats] of Object.entries(data.reads || {})) {
    for (const chatId of Object.keys(chats || {})) {
      add('read', chatId + '|' + ownerId, 'snapshot_reads',
        chatId + '|' + ownerId, 'reads.json');
    }
  }
  for (const [ownerId, friends] of Object.entries(data.friendMeta || {})) {
    for (const friendId of Object.keys(friends || {})) {
      add('friend_meta', ownerId + '|' + friendId, 'snapshot_friendMeta',
        ownerId + '|' + friendId, 'friendmeta.json');
    }
  }
  for (const moment of data.moments || []) {
    add('moment', moment && moment.id, 'moment', moment && moment.id, 'moments.json');
    for (const comment of moment && moment.comments || []) {
      add('moment_comment', moment.id + '|' + comment.id, 'moment_comment',
        moment.id + '|' + comment.id, 'moments.json');
      for (const like of comment.likes || []) {
        add('moment_comment_like',
          moment.id + '|' + comment.id + '|' + like.userId,
          'moment_comment_like',
          moment.id + '|' + comment.id + '|' + like.userId,
          'moments.json');
      }
    }
    for (const like of moment && moment.likes || []) {
      add('moment_like', moment.id + '|' + like.userId, 'moment_like',
        moment.id + '|' + like.userId, 'moments.json');
    }
  }
  for (const notice of data.momentNotices || []) {
    add('moment_notice', notice && notice.id, 'moment_notice',
      notice && notice.id, 'moment-notices.json');
  }
  for (const chatId of data.messageThreads || []) {
    add('message_thread', chatId, 'chat', chatId, 'messages');
  }

  const byType = {};
  const byShard = Array.from({ length: shardCount }, () => ({
    total: 0,
    byType: {}
  }));
  for (const row of rows) {
    byType[row.entityType] = (byType[row.entityType] || 0) + 1;
    byShard[row.owner].total += 1;
    byShard[row.owner].byType[row.entityType] =
      (byShard[row.owner].byType[row.entityType] || 0) + 1;
  }
  rows.sort((left, right) =>
    left.owner - right.owner
    || left.entityType.localeCompare(right.entityType)
    || left.id.localeCompare(right.id)
  );
  const deterministic = {
    version: 1,
    topologyId: String(routePlan.topologyId || ''),
    routePlanHash: String(routePlan.hash || ''),
    shardCount,
    itemCount: rows.length,
    byType,
    byShard
  };
  return Object.assign({
    ok: failures.length === 0,
    failures: failures.slice(0, 500),
    hash: hash(deterministic)
  }, deterministic, { items: rows });
}

module.exports = { buildPlacementPlan, ownerFor };
