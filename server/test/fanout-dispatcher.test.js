'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { FanoutOutbox } = require('../lib/fanout-outbox');
const { FanoutDispatcher } = require('../lib/fanout-dispatcher');

async function main() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-fanout-dispatcher-'));
  const outbox = new FanoutOutbox({
    file: path.join(dir, 'outbox.jsonl'),
    now: () => 1000
  });
  let calls = 0;
  const dispatcher = new FanoutDispatcher({
    outbox,
    maxBackoffMs: 4000,
    bus: {
      async publish(input) {
        calls += 1;
        if (calls === 1) {
          return { ok: false, results: [{ nodeId: 'gw-a', ok: false, error: 'down' }] };
        }
        return { ok: true, delivered: 2, results: [{ nodeId: 'gw-a', ok: true }] };
      }
    }
  });
  outbox.enqueue({
    publishId: 'p-1',
    payload: { type: 'message' },
    nodes: [{ id: 'gw-a', endpoint: 'http://gw-a', userIds: ['u1', 'u2'] }]
  });
  const first = await dispatcher.flush();
  assert.equal(first.failed, 1);
  assert.equal(outbox.snapshot().pending, 1);
  const retry = await dispatcher.flush({ limit: 10 });
  assert.equal(retry.scanned, 0);
  fs.rmSync(dir, { recursive: true, force: true });
  console.log('fanout-dispatcher: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
