'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const SERVER_DIR = path.resolve(__dirname, '..');
const PASSWORD = 'LargeGroup10000!';
const MEMBER_COUNT = 10000;
const PAGE_SIZE = 100;
const CHAT_ID = 'c_group_runtime_10000';

function freePort() {
  return new Promise((resolve, reject) => {
    const socket = net.createServer();
    socket.once('error', reject);
    socket.listen(0, '127.0.0.1', () => {
      const port = socket.address().port;
      socket.close(() => resolve(port));
    });
  });
}

function account(id, username, nickname) {
  const salt = crypto.randomBytes(16).toString('hex');
  return {
    id,
    username,
    nickname,
    avatar: '',
    bio: '',
    phone: '',
    gender: 'secret',
    balance: 0,
    transferLimit: 20000,
    salt,
    passwordHash: crypto.scryptSync(PASSWORD, salt, 64).toString('hex'),
    createdAt: '2026-01-01T00:00:00.000Z',
    tokenVersion: 0,
    phoneSession: 0
  };
}

function member(index) {
  return {
    id: 'u_group_10000_member_' + index,
    username: 'group_10000_member_' + index,
    nickname: 'Member ' + index,
    avatar: '',
    bio: '',
    phone: '',
    gender: 'secret',
    balance: 0,
    transferLimit: 20000,
    createdAt: '2026-01-01T00:00:00.000Z',
    tokenVersion: 0,
    phoneSession: 0
  };
}

async function waitForHealth(base, child, logs) {
  for (let index = 0; index < 240; index += 1) {
    if (child.exitCode !== null) {
      throw new Error('large-group server exited:\n' + logs.join(''));
    }
    try {
      if ((await fetch(base + '/api/health')).ok) return;
    } catch (_) {
      // Server is still starting with the 10k-user fixture.
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('large-group server start timeout:\n' + logs.join(''));
}

async function call(base, cookie, method, url, body, deviceId) {
  const headers = {
    'x-device-kind': 'desktop',
    'x-device-id': deviceId || 'large-group-test'
  };
  if (cookie) headers.Cookie = cookie;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const started = process.hrtime.bigint();
  const response = await fetch(base + url, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await response.text();
  const elapsedMs = Number(process.hrtime.bigint() - started) / 1e6;
  let envelope = {};
  try { envelope = text ? JSON.parse(text) : {}; } catch (_) { envelope = { raw: text }; }
  const data = envelope && envelope.data !== undefined ? envelope.data : envelope;
  return { status: response.status, data, headers: response.headers, elapsedMs };
}

async function login(base, username) {
  const response = await call(base, '', 'POST', '/api/login', {
    username,
    password: PASSWORD
  }, username + '-device');
  assert.strictEqual(response.status, 200, JSON.stringify(response.data));
  const cookie = (response.headers.getSetCookie
    ? response.headers.getSetCookie()[0]
    : response.headers.get('set-cookie') || '').split(';')[0];
  assert.ok(cookie, 'login did not return a session cookie');
  return { cookie, user: response.data.user };
}

function openSocket(base, cookie) {
  const pair = String(cookie || '').split(';')
    .map((part) => part.trim())
    .find((part) => part.includes('=')) || '';
  const token = pair.slice(pair.indexOf('=') + 1);
  assert.ok(token, 'cookie did not contain a socket token');
  const events = [];
  const socket = new WebSocket(base.replace(/^http/, 'ws') + '/?token=' + encodeURIComponent(token));
  socket.addEventListener('message', (event) => {
    try { events.push(JSON.parse(String(event.data || ''))); } catch (_) {}
  });
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('websocket ready timeout')), 8000);
    socket.addEventListener('error', () => {
      clearTimeout(timer);
      reject(new Error('websocket failed'));
    });
    socket.addEventListener('message', (event) => {
      try {
        if (JSON.parse(String(event.data || '')).type === 'ready') {
          clearTimeout(timer);
          resolve({ socket, events });
        }
      } catch (_) {}
    });
  });
}

async function waitForEvent(events, predicate, timeoutMs) {
  const deadline = Date.now() + (timeoutMs || 8000);
  while (Date.now() < deadline) {
    const event = events.find(predicate);
    if (event) return event;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error('websocket event timeout');
}

function trackSlowest(samples, name, elapsedMs) {
  samples.push({ name, elapsedMs: Math.round(elapsedMs * 10) / 10 });
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-large-group-10000-'));
  const messageDir = path.join(dataDir, 'messages');
  fs.mkdirSync(messageDir, { recursive: true });
  const port = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  let child;
  let sockets = [];

  try {
    const owner = account('u_group_10000_owner', 'group_10000_owner', 'Owner');
    const sender = account('u_group_10000_sender', 'group_10000_sender', 'Sender');
    const recipientA = account('u_group_10000_recipient_a', 'group_10000_recipient_a', 'Recipient A');
    const recipientB = account('u_group_10000_recipient_b', 'group_10000_recipient_b', 'Recipient B');
    const joinCandidate = account('u_group_10000_join', 'group_10000_join', 'Join Candidate');
    const filler = [];
    for (let index = 0; index < MEMBER_COUNT - 4; index += 1) filler.push(member(index));
    const users = [owner, sender, recipientA, recipientB, joinCandidate].concat(filler);
    const memberIds = [owner.id, sender.id, recipientA.id, recipientB.id]
      .concat(filler.map((user) => user.id));
    assert.strictEqual(new Set(memberIds).size, MEMBER_COUNT);

    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({ users }), 'utf8');
    fs.writeFileSync(path.join(dataDir, 'friendships.json'), JSON.stringify({ friendships: [] }), 'utf8');
    fs.writeFileSync(path.join(dataDir, 'chats.json'), JSON.stringify({
      chats: [{
        id: CHAT_ID,
        type: 'group',
        name: '10,000 member runtime',
        avatar: '',
        memberIds,
        ownerId: owner.id,
        seq: 0,
        createdAt: '2026-01-01T00:00:00.000Z',
        pinnedFor: [],
        mutedFor: [],
        muteMembers: [],
        aliases: {}
      }]
    }), 'utf8');
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({ sliderLogin: 0 }), 'utf8');
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }), 'utf8');
    fs.writeFileSync(path.join(dataDir, 'im.json'), JSON.stringify({
      allowStranger: true,
      maxGroupMembers: MEMBER_COUNT
    }), 'utf8');

    child = spawn(process.execPath, ['server.js'], {
      cwd: SERVER_DIR,
      env: Object.assign({}, process.env, {
        DATA_DIR: dataDir,
        PORT: String(port),
        TURN_PORT: String(turnPort),
        CHRIS_LOCAL_ONLY: '1',
        AML_RUNTIME_ENABLED: '0',
        DISABLE_STARTUP_BOT_BACKFILL: '1',
        MESSAGE_RELIABILITY_ENABLED: '1'
      }),
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });
    child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
    child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
    await waitForHealth(base, child, logs);

    const ownerSession = await login(base, owner.username);
    const senderSession = await login(base, sender.username);
    const recipientASession = await login(base, recipientA.username);
    const recipientBSession = await login(base, recipientB.username);
    const joinSession = await login(base, joinCandidate.username);
    sockets = await Promise.all([
      openSocket(base, ownerSession.cookie),
      openSocket(base, senderSession.cookie),
      openSocket(base, recipientASession.cookie),
      openSocket(base, recipientBSession.cookie)
    ]);
    const ownerSocket = sockets[0];
    const recipientASocket = sockets[2];
    const recipientBSocket = sockets[3];
    const latencySamples = [];

    let response = await call(base, ownerSession.cookie, 'GET', '/api/chats');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const initialSummary = (response.data.chats || []).find((chat) => chat.id === CHAT_ID);
    assert.ok(initialSummary, 'large group was missing from the conversation list');
    assert.strictEqual(initialSummary.memberCount, MEMBER_COUNT);
    assert.strictEqual(initialSummary.memberIds.length, 64);
    assert.strictEqual(initialSummary.memberIdsTruncated, true);

    const seenMembers = new Set();
    let cursor = 0;
    let pages = 0;
    let pageTotalMs = 0;
    do {
      response = await call(base, ownerSession.cookie, 'GET',
        '/api/chats/' + CHAT_ID + '/members?limit=' + PAGE_SIZE + '&cursor=' + cursor);
      assert.strictEqual(response.status, 200, JSON.stringify(response.data));
      assert.strictEqual(response.data.memberCount, MEMBER_COUNT);
      for (const user of response.data.members || []) {
        assert.strictEqual(seenMembers.has(user.id), false, 'member pagination returned a duplicate');
        seenMembers.add(user.id);
      }
      cursor = response.data.nextCursor;
      pages += 1;
      pageTotalMs += response.elapsedMs;
      assert.ok(response.elapsedMs < 2500,
        'member page exceeded 2.5s: ' + response.elapsedMs.toFixed(1) + 'ms');
    } while (response.data.hasMore);
    assert.strictEqual(seenMembers.size, MEMBER_COUNT);
    assert.strictEqual(pages, MEMBER_COUNT / PAGE_SIZE);
    trackSlowest(latencySamples, '100 member pages', pageTotalMs);

    response = await call(base, senderSession.cookie, 'POST',
      '/api/chats/' + CHAT_ID + '/messages', {
        kind: 'text',
        content: 'first large group message',
        clientId: 'large-group-first',
        mentions: []
      });
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    trackSlowest(latencySamples, 'message 1', response.elapsedMs);
    let event = await waitForEvent(recipientASocket.events, (row) =>
      row.type === 'message' && row.message && row.message.clientId === 'large-group-first');
    response = await call(base, recipientASession.cookie, 'GET', '/api/chats');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(
      (response.data.chats || []).find((chat) => chat.id === CHAT_ID).unread,
      1
    );

    response = await call(base, senderSession.cookie, 'POST',
      '/api/chats/' + CHAT_ID + '/messages', {
        kind: 'text',
        content: 'second large group message',
        clientId: 'large-group-second',
        mentions: []
      });
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    trackSlowest(latencySamples, 'message 2', response.elapsedMs);
    event = await waitForEvent(recipientBSocket.events, (row) =>
      row.type === 'message' && row.message && row.message.clientId === 'large-group-second');
    response = await call(base, recipientBSession.cookie, 'GET', '/api/chats');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(
      (response.data.chats || []).find((chat) => chat.id === CHAT_ID).unread,
      2
    );

    response = await call(base, senderSession.cookie, 'POST',
      '/api/chats/' + CHAT_ID + '/messages', {
        kind: 'text',
        content: '@Recipient A large group mention',
        clientId: 'large-group-mention',
        mentions: [recipientA.id]
      });
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    trackSlowest(latencySamples, 'explicit mention', response.elapsedMs);
    event = await waitForEvent(recipientASocket.events, (row) =>
      row.type === 'message' && row.message && row.message.clientId === 'large-group-mention');
    assert.strictEqual(event.message.mentions.includes(recipientA.id), true);
    response = await call(base, recipientASession.cookie, 'GET', '/api/chats');
    const mentionChat = (response.data.chats || []).find((chat) => chat.id === CHAT_ID);
    assert.strictEqual(mentionChat.lastMessage.mentionMe, true);
    assert.strictEqual(mentionChat.unread, 3);

    response = await call(base, ownerSession.cookie, 'POST',
      '/api/chats/' + CHAT_ID + '/messages', {
        kind: 'text',
        content: '@所有人 10k broadcast',
        clientId: 'large-group-all',
        mentions: []
      });
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    trackSlowest(latencySamples, '@all', response.elapsedMs);
    event = await waitForEvent(recipientBSocket.events, (row) =>
      row.type === 'message' && row.message && row.message.clientId === 'large-group-all');
    assert.strictEqual(event.message.mentionAll, true);
    assert.strictEqual(event.message.mentions, undefined);
    response = await call(base, recipientBSession.cookie, 'GET', '/api/chats');
    const allChat = (response.data.chats || []).find((chat) => chat.id === CHAT_ID);
    assert.strictEqual(allChat.lastMessage.mentionMe, true);
    assert.strictEqual(allChat.unread, 4);
    assert.ok(event.message.content.indexOf('@所有人') >= 0);

    for (let index = 0; index < 45; index += 1) {
      response = await call(base, senderSession.cookie, 'POST',
        '/api/chats/' + CHAT_ID + '/messages', {
          kind: 'text',
          content: 'large group trailing message ' + index,
          clientId: 'large-group-trailing-' + index,
          mentions: []
        });
      assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    }
    response = await call(base, recipientASession.cookie, 'GET', '/api/chats');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    let mentionRow = (response.data.chats || []).find((row) => row.id === CHAT_ID);
    assert.strictEqual(mentionRow.lastMessage.mentionMe, true,
      'an unread mention must survive more than forty newer group messages');
    assert.ok(mentionRow.lastMessage.preview.indexOf('trailing message 44') >= 0,
      'the preview must remain the latest message while the mention marker persists');

    response = await call(base, recipientBSession.cookie, 'GET', '/api/chats');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    mentionRow = (response.data.chats || []).find((row) => row.id === CHAT_ID);
    assert.strictEqual(mentionRow.lastMessage.mentionMe, true,
      'an unread @all marker must also survive more than forty newer messages');

    response = await call(base, ownerSession.cookie, 'POST', '/api/chats/' + CHAT_ID + '/invite', {});
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const inviteCode = response.data.code;
    response = await call(base, joinSession.cookie, 'POST', '/api/join', { code: inviteCode });
    assert.strictEqual(response.status, 422,
      'a 10,000-member group must reject one more member: ' + JSON.stringify(response.data));

    response = await call(base, ownerSession.cookie, 'POST',
      '/api/chats/' + CHAT_ID + '/muteall', { on: true });
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.muteAll, true);
    trackSlowest(latencySamples, 'mute all', response.elapsedMs);

    response = await call(base, ownerSession.cookie, 'PATCH',
      '/api/chats/' + CHAT_ID + '/info', { announce: 'Large-group runtime verified' });
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    trackSlowest(latencySamples, 'announce', response.elapsedMs);

    const removedId = filler[0].id;
    response = await call(base, ownerSession.cookie, 'POST',
      '/api/chats/' + CHAT_ID + '/kick', { userId: removedId });
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.memberCount, MEMBER_COUNT - 1);
    trackSlowest(latencySamples, 'kick', response.elapsedMs);

    response = await call(base, ownerSession.cookie, 'POST',
      '/api/chats/' + CHAT_ID + '/add-members', { userIds: [removedId] });
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.memberCount, MEMBER_COUNT);
    trackSlowest(latencySamples, 'add member', response.elapsedMs);

    const slowest = Math.max(...latencySamples.map((row) => row.elapsedMs));
    assert.ok(slowest < 5000, 'large-group operation exceeded 5s: '
      + JSON.stringify(latencySamples));
    console.log(JSON.stringify({
      members: MEMBER_COUNT,
      pages,
      pageTotalMs: Math.round(pageTotalMs * 10) / 10,
      latencySamples,
      slowestMs: slowest
    }));
    console.log('large-group-10000: passed');
  } finally {
    sockets.forEach(({ socket }) => {
      try { socket.close(); } catch (_) {}
    });
    if (child && child.exitCode === null) child.kill();
    await new Promise((resolve) => setTimeout(resolve, 200));
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
