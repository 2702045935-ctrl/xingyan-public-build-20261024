'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const {
  PaymentSettlementScheduler,
  shanghaiDate
} = require('../lib/payment-settlement-scheduler');

async function main() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-settlement-'));
  const file = path.join(dir, 'runs.json');
  let calls = 0;
  const provider = {
    name: 'licensed-test-provider',
    ready: () => true,
    async settlementReport(date) {
      calls += 1;
      return [{ orderId: 'fund_1', date }];
    }
  };
  const database = {
    reconcileProviderSettlement(name, date, lines) {
      assert.strictEqual(name, provider.name);
      assert.strictEqual(date, '2026-11-19');
      assert.strictEqual(lines.length, 1);
      return {
        providerLines: lines.length,
        localLines: 1,
        mismatches: []
      };
    }
  };
  const now = new Date('2026-11-20T02:00:00.000Z');
  const scheduler = new PaymentSettlementScheduler({
    provider,
    database,
    file,
    now: () => now
  });
  assert.strictEqual(shanghaiDate(now, 0), '2026-11-20');
  assert.strictEqual(shanghaiDate(now, -1), '2026-11-19');

  const first = await scheduler.run('2026-11-19');
  assert.strictEqual(first.duplicate, false);
  assert.strictEqual(first.run.status, 'succeeded');
  assert.strictEqual(first.run.mismatches, 0);
  assert.strictEqual(calls, 1);

  const second = await scheduler.run('2026-11-19');
  assert.strictEqual(second.duplicate, true);
  assert.strictEqual(calls, 1);

  const failingProvider = {
    name: 'licensed-test-provider',
    ready: () => true,
    async settlementReport() {
      throw new Error('provider unavailable');
    }
  };
  const retryScheduler = new PaymentSettlementScheduler({
    provider: failingProvider,
    database,
    file: path.join(dir, 'retry-runs.json'),
    now: () => now
  });
  await assert.rejects(() => retryScheduler.run('2026-11-20'),
    /provider unavailable/);
  assert.strictEqual(retryScheduler.latest().status, 'failed');

  try {
    fs.rmSync(dir, { recursive: true, force: true });
  } catch (_) {
    /* Windows keep-open fallback */
  }
  console.log('payment-settlement-scheduler: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
