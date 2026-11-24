'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { FanoutOutbox } = require('../lib/fanout-outbox');

function main() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-fanout-outbox-'));
  const file = path.join(dir, 'fanout.jsonl');
  let clock = 1000;
  const options = {
    file,
    now: () => clock,
    uid: (() => {
      let seq = 0;
      return (prefix) => `${prefix}-${++seq}`;
    })()
  };
  const outbox = new FanoutOutbox(options);
  const first = outbox.enqueue({
    publishId: 'p-1',
    chatId: 'c-1',
    payload: { type: 'message' },
    nodes: [{ id: 'gw-a', userIds: ['u1'] }]
  });
  assert.equal(first.duplicate, false);
  assert.equal(outbox.enqueue({ publishId: 'p-1', chatId: 'c-1' }).duplicate, true);
  assert.equal(outbox.ready(10).length, 1);
  outbox.attempt(first.entry.id);
  outbox.fail(first.entry.id, 'network', clock + 2000);
  assert.equal(outbox.ready(10).length, 0);
  clock = 3001;
  assert.equal(outbox.ready(10).length, 1);
  outbox.ack(first.entry.id);
  assert.equal(outbox.snapshot().acked, 1);

  const replay = new FanoutOutbox(options);
  assert.equal(replay.snapshot().acked, 1);
  assert.equal(replay.snapshot().pending, 0);
  fs.rmSync(dir, { recursive: true, force: true });
  console.log('fanout-outbox: passed');
}

main();
