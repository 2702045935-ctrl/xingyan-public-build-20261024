'use strict';

const assert = require('assert');
const { SignedPaymentProviderBridge } = require('../lib/payment-provider');
const { evaluatePaymentReadiness } = require('../lib/payment-readiness');

function provider(overrides) {
  return new SignedPaymentProviderBridge(Object.assign({
    name: 'licensed-test',
    baseUrl: 'https://payments.example.test',
    apiKey: 'request-secret',
    webhookSecret: 'webhook-secret',
    fetch: async () => new Response('{}', { status: 200 }),
    allowInsecure: false
  }, overrides || {}));
}

function input(overrides) {
  return Object.assign({
    mode: 'enforce',
    database: true,
    databaseReady: true,
    keyringReady: true,
    provider: provider(),
    providerReady: true,
    amlEnabled: true,
    amlHealthy: true
  }, overrides || {});
}

async function main() {
  assert.strictEqual(evaluatePaymentReadiness(input()).ready, true);

  const disabled = evaluatePaymentReadiness(input({
    amlEnabled: false,
    keyringReady: false
  }));
  assert.strictEqual(disabled.ready, false);
  assert.ok(disabled.blockers.includes('aml_enforcement_disabled'));
  assert.ok(disabled.blockers.includes('payment_keyring_missing'));

  const insecureProvider = provider({
    baseUrl: 'http://payments.example.test',
    allowInsecure: false
  });
  assert.strictEqual(insecureProvider.ready(), false);
  assert.ok(insecureProvider.readiness().blockers.includes(
    'payment_provider_https_required'
  ));

  const sandboxProvider = provider({
    baseUrl: 'http://127.0.0.1:12345',
    allowInsecure: true
  });
  assert.strictEqual(sandboxProvider.ready(), true);

  let aborted = false;
  const timeoutProvider = provider({
    baseUrl: 'http://127.0.0.1:12345',
    allowInsecure: true,
    requestTimeoutMs: 1000,
    fetch: (_url, options) => new Promise((resolve, reject) => {
      options.signal.addEventListener('abort', () => {
        aborted = true;
        const error = new Error('aborted');
        error.name = 'AbortError';
        reject(error);
      });
    })
  });
  const startedAt = Date.now();
  await assert.rejects(
    timeoutProvider.createDeposit({
      id: 'timeout-order',
      amountCents: 100,
      currency: 'CNY',
      userId: 'timeout-user'
    }),
    /timed out/
  );
  assert.strictEqual(aborted, true);
  assert.ok(Date.now() - startedAt >= 900);

  console.log('payment-readiness: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
