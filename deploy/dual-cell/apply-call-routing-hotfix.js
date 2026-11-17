'use strict';

const fs = require('fs');
const path = require('path');

const input = process.argv[2];
const output = process.argv[3];
if (!input || !output) {
  throw new Error('usage: node apply-call-routing-hotfix.js INPUT OUTPUT');
}

let source = fs.readFileSync(input, 'utf8');

function replaceOnce(label, needle, replacement) {
  const first = source.indexOf(needle);
  if (first < 0) throw new Error('missing marker: ' + label);
  if (source.indexOf(needle, first + needle.length) >= 0) {
    throw new Error('ambiguous marker: ' + label);
  }
  source = source.slice(0, first) + replacement + source.slice(first + needle.length);
}

replaceOnce(
  'findUser',
  'const findUser = (id) => {',
  [
    '/* Cross-shard call snapshots are short-lived transport objects. */',
    'const remoteCallUsers = new Map();',
    'const findUser = (id) => {'
  ].join('\n')
);

replaceOnce(
  'findUser return',
  'return usersById.get(id) || loadUserSnapshot(id) || null;',
  [
    'return usersById.get(id) || loadUserSnapshot(id)',
    '    || remoteCallUsers.get(String(id || "")) || null;'
  ].join('\n')
);

replaceOnce(
  'call branch',
  '    const callId = str(msg.callId, 60);',
  [
    '    const callId = str(msg.callId, 60);',
    '    if (String(msg.action || "") === "invite" && msg.toUserId) {',
    '      const targetId = str(msg.toUserId, 40);',
    '      if (targetId && !findUser(targetId)) {',
    '        remoteCallUsers.set(targetId, remoteCallUserSnapshot(targetId, {',
    '          nickname: str(msg.peerName, 40) || "对方",',
    '          avatar: str(msg.peerAvatar, 300)',
    '        }));',
    '      }',
    '    }'
  ].join('\n')
);

replaceOnce(
  'callctl find user',
  '      const u = findUser(str(p.userId, 40));\n      if (!u) return;',
  [
    '      const relayUserId = str(p.userId, 40);',
    '      let u = findUser(relayUserId);',
    '      if (!u && p.user && String(p.user.id || "") === relayUserId) {',
    '        u = remoteCallUserSnapshot(relayUserId, p.user);',
    '        remoteCallUsers.set(relayUserId, u);',
    '      }',
    '      if (!u) return;'
  ].join('\n')
);

const callCtlNeedle = [
  '          BUS.sendToShard(shardName(i), {',
  '            type: \'callctl\', userId: user.id, build: socket.__appBuild || \'\',',
  '            raw: JSON.stringify(msg)',
  '          });'
].join('\n');
const callCtlReplacement = [
  '          BUS.sendToShard(shardName(i), {',
  '            type: \'callctl\', userId: user.id, build: socket.__appBuild || \'\',',
  '            user: remoteCallUserSnapshot(user.id, user),',
  '            raw: JSON.stringify(msg)',
  '          });'
].join('\n');
replaceOnce('callctl fallback snapshot', callCtlNeedle, callCtlReplacement);

const ownerNeedle = [
  '        BUS.sendToShard(shardName(ownerShard), {',
  '          type: \'callctl\', userId: user.id, build: socket.__appBuild || \'\',',
  '          raw: JSON.stringify(msg)',
  '        });'
].join('\n');
const ownerReplacement = [
  '        BUS.sendToShard(shardName(ownerShard), {',
  '          type: \'callctl\', userId: user.id, build: socket.__appBuild || \'\',',
  '          user: remoteCallUserSnapshot(user.id, user),',
  '          raw: JSON.stringify(msg)',
  '        });'
].join('\n');
replaceOnce('callctl owner snapshot', ownerNeedle, ownerReplacement);

replaceOnce(
  'remote snapshot helper',
  'function findUserByName(username) {',
  [
    'function remoteCallUserSnapshot(id, source) {',
    '  const row = source && typeof source === "object" ? source : {};',
    '  return {',
    '    id: String(id || row.id || ""),',
    '    username: String(row.username || ""),',
    '    nickname: String(row.nickname || row.username || "对方"),',
    '    avatar: String(row.avatar || ""),',
    '    banned: row.banned === true,',
    '    __remoteAt: Date.now(),',
    '    __remoteCall: true',
    '  };',
    '}',
    '',
    'function findUserByName(username) {'
  ].join('\n')
);

replaceOnce(
  'friend check',
  '      if (!friendIds(user.id).includes(target.id)) {',
  '      if (!user.__remoteCall && !target.__remoteCall\n          && !friendIds(user.id).includes(target.id)) {'
);

const cleanup = [
  '',
  'setInterval(() => {',
  '  const cutoff = Date.now() - 10 * 60 * 1000;',
  '  remoteCallUsers.forEach((row, id) => {',
  '    if (Number(row.__remoteAt || 0) < cutoff) remoteCallUsers.delete(id);',
  '  });',
  '}, 60 * 1000).unref();',
  ''
].join('\n');
const helperEnd = source.indexOf('function findUserByName(username) {');
const blockEnd = source.indexOf('}', helperEnd);
if (helperEnd < 0 || blockEnd < 0) throw new Error('missing remote snapshot helper');
source = source.slice(0, blockEnd + 1) + cleanup + source.slice(blockEnd + 1);

const tmp = path.resolve(output) + '.tmp';
fs.writeFileSync(tmp, source, 'utf8');
fs.renameSync(tmp, path.resolve(output));
console.log('patched:', path.resolve(output));
