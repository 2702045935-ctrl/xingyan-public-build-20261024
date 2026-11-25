#!/usr/bin/env node
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const {
  GroupMembershipDirectory
} = require('../lib/group-membership-directory');

function digestMembers(members) {
  return crypto.createHash('sha256')
    .update(members.join('\u0000'))
    .digest('hex');
}

function readGroups(chatsFile, limit) {
  const source = JSON.parse(fs.readFileSync(chatsFile, 'utf8'));
  const chats = Array.isArray(source && source.chats) ? source.chats : [];
  const groups = chats.filter((chat) =>
    chat && chat.type === 'group'
      && Array.isArray(chat.memberIds)
      && chat.memberIds.length > 0);
  const selected = Number(limit) > 0 ? groups.slice(0, Number(limit)) : groups;
  return {
    totalChats: chats.length,
    totalGroups: groups.length,
    selected
  };
}

async function runMigration(options) {
  const opts = options || {};
  const chatsFile = path.resolve(String(opts.chatsFile || ''));
  const root = path.resolve(String(opts.root || ''));
  if (!opts.chatsFile || !opts.root) {
    throw new Error('chatsFile and root are required');
  }
  const started = Date.now();
  const source = readGroups(chatsFile, opts.limit);
  const report = {
    version: 1,
    isolated: opts.apply !== true,
    applied: opts.apply === true,
    chatsFile,
    root,
    totalChats: source.totalChats,
    totalGroups: source.totalGroups,
    selectedGroups: source.selected.length,
    groups: [],
    totalMembers: 0,
    errors: []
  };
  const directory = opts.apply === true
    ? new GroupMembershipDirectory({
        root,
        shardSize: opts.shardSize || 1000,
        maxMembers: opts.maxMembers || 10000
      })
    : null;

  for (const chat of source.selected) {
    const chatId = String(chat.id || '');
    try {
      const members = Array.from(new Set(chat.memberIds.map(String)));
      const memberDigest = digestMembers(members);
      const row = {
        chatId,
        memberCount: members.length,
        memberDigest
      };
      if (directory) {
        const manifest = directory.install(chatId, members, {
          shardSize: opts.shardSize || 1000
        });
        if (manifest.memberCount !== members.length
            || manifest.memberDigest !== memberDigest) {
          throw new Error('installed membership manifest differs from source');
        }
        const roundTrip = directory.all(chatId);
        if (digestMembers(roundTrip) !== memberDigest) {
          throw new Error('round-trip membership digest differs from source');
        }
        const page = directory.page(chatId, 0, Math.min(100, members.length));
        if (page.members[0] !== members[0]
            || page.members[page.members.length - 1]
              !== members[Math.min(99, members.length - 1)]) {
          throw new Error('first membership page differs from source');
        }
        row.generation = manifest.generation;
        row.shardCount = manifest.shardCount;
      }
      report.groups.push(row);
      report.totalMembers += members.length;
    } catch (error) {
      report.errors.push({
        chatId,
        error: String(error && error.message || error)
      });
    }
  }
  report.durationMs = Date.now() - started;
  report.pass = report.errors.length === 0;
  if (opts.out) {
    const out = path.resolve(String(opts.out));
    fs.mkdirSync(path.dirname(out), { recursive: true });
    fs.writeFileSync(out, JSON.stringify(report, null, 2) + '\n', 'utf8');
  }
  return report;
}

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const found = process.argv.slice(2).find((value) => value.startsWith(prefix));
  return found ? found.slice(prefix.length) : fallback;
}

async function main() {
  const report = await runMigration({
    chatsFile: arg('chats', ''),
    root: arg('root', ''),
    out: arg('out', ''),
    limit: Number(arg('limit', '0')) || 0,
    shardSize: Number(arg('shard-size', '1000')) || 1000,
    apply: process.argv.includes('--apply')
  });
  console.log(JSON.stringify(report, null, 2));
  if (!report.pass) process.exitCode = 2;
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error && error.stack || error);
    process.exitCode = 1;
  });
}

module.exports = {
  digestMembers,
  readGroups,
  runMigration
};
