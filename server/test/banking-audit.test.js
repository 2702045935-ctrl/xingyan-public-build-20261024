'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { BankingAuditLog } = require('../lib/banking-audit');

function append(log, index, context) {
  return log.append({
    requestId: `req-${index}`,
    actor: {
      id: `ops-${index}`,
      username: 'auditor',
      name: '审计员',
      role: '超级管理员'
    },
    source: {
      ip: '127.0.0.1',
      userAgent: 'banking-audit-test'
    },
    category: index % 2 ? 'finance' : 'security',
    severity: index === 2 ? 'high' : 'normal',
    outcome: 'success',
    action: `action-${index}`,
    target: `target-${index}`,
    detail: `detail-${index}`,
    context
  });
}

function main() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-banking-audit-'));
  const file = path.join(dir, 'audit-bank.jsonl');
  const log = new BankingAuditLog({
    file,
    stateFile: path.join(dir, 'audit-bank-state.json'),
    secret: 'banking-audit-test-secret',
    now: (() => {
      let tick = 0;
      return () => new Date(Date.UTC(2026, 10, 24, 1, 0, tick++)).toISOString();
    })(),
    uid: (() => {
      let seq = 0;
      return (prefix) => `${prefix}-${++seq}`;
    })()
  });

  const first = append(log, 1, { amount: 100, currency: 'CNY' });
  const second = append(log, 2, { amount: 200.5, currency: 'CNY' });
  const third = append(log, 3, { frozen: true });
  assert.equal(first.prevHash, '');
  assert.equal(second.prevHash, first.hash);
  assert.equal(third.prevHash, second.hash);
  assert.equal(third.seq, 3);

  const verified = log.verify();
  assert.equal(verified.ok, true, JSON.stringify(verified.failures));
  assert.equal(verified.checked, 3);
  assert.equal(verified.tailHash, third.hash);

  const finance = log.read({ category: 'finance', limit: 20 });
  assert.equal(finance.total, 2);
  assert.equal(finance.rows[0].actor.username, 'auditor');
  assert.equal(finance.rows[0].source.ip, '127.0.0.1');

  const exported = log.export({ limit: 20 });
  assert.equal(exported.manifest.count, 3);
  assert.equal(exported.manifest.firstSeq, 1);
  assert.equal(exported.manifest.lastSeq, 3);
  assert.match(exported.manifest.manifestMac, /^[a-f0-9]{64}$/);

  const lines = fs.readFileSync(file, 'utf8').trim().split('\n');
  const tampered = JSON.parse(lines[1]);
  tampered.detail = 'tampered';
  lines[1] = JSON.stringify(tampered);
  fs.writeFileSync(file, lines.join('\n') + '\n');
  const broken = log.verify();
  assert.equal(broken.ok, false);
  assert.ok(broken.failures.some((row) => row.code === 'bad-hmac'
    || row.code === 'broken-chain'));

  const failDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-banking-audit-fail-'));
  const blockedFile = path.join(failDir, 'audit-bank.jsonl');
  fs.mkdirSync(blockedFile);
  const failClosed = new BankingAuditLog({
    file: blockedFile,
    stateFile: path.join(failDir, 'audit-bank-state.json'),
    secret: 'banking-audit-test-secret'
  });
  assert.throws(
    () => append(failClosed, 1, { amount: 1 }),
    /EISDIR|illegal operation|directory/i,
    'journal write failures must propagate and block business success'
  );

  fs.rmSync(dir, { recursive: true, force: true });
  fs.rmSync(failDir, { recursive: true, force: true });
  console.log('banking-audit: passed');
}

main();
