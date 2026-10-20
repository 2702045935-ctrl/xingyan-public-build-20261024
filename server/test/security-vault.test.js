'use strict';


const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { createSecurityVault } = require('../lib/security-vault');

async function main() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-vault-test-'));
  try {
    const vault = createSecurityVault({ dataDir: dir, rootMaterial: 'test-root' });
    const legacyKey = crypto.createHmac('sha256', 'test-root').update('msg:chat-1').digest();
    const legacyEnvelope = {
      e: 1,
      iv: Buffer.alloc(12, 1).toString('base64'),
      tag: '',
      ct: ''
    };
    const legacyCipher = crypto.createCipheriv('aes-256-gcm', legacyKey,
      Buffer.from(legacyEnvelope.iv, 'base64'));
    legacyEnvelope.ct = Buffer.concat([
      legacyCipher.update(Buffer.from(JSON.stringify({ id: 'legacy' }), 'utf8')),
      legacyCipher.final()
    ]).toString('base64');
    legacyEnvelope.tag = legacyCipher.getAuthTag().toString('base64');
    assert.deepStrictEqual(
      vault.openJson('message', 'chat-1', legacyEnvelope, legacyKey),
      { id: 'legacy' }
    );

    const first = vault.sealJson('message', 'chat-1', { id: 'version-1' });
    assert.strictEqual(first.kv, 1);
    assert.deepStrictEqual(vault.openJson('message', 'chat-1', first, null), { id: 'version-1' });

    const rotated = vault.rotate('message', 'test-suite', 'automated rotation');
    assert.strictEqual(rotated.active, 2);
    const second = vault.sealJson('message', 'chat-1', { id: 'version-2' });
    assert.strictEqual(second.kv, 2);
    assert.deepStrictEqual(vault.openJson('message', 'chat-1', second, null), { id: 'version-2' });
    assert.deepStrictEqual(vault.openJson('message', 'chat-1', first, null), { id: 'version-1' });
    assert.strictEqual(vault.verifyAudit().ok, true);

    const auditFile = path.join(dir, 'security-audit.jsonl');
    const lines = fs.readFileSync(auditFile, 'utf8').split('\n').filter(Boolean);
    const tampered = JSON.parse(lines[lines.length - 1]);
    tampered.details.reason = 'tampered';
    lines[lines.length - 1] = JSON.stringify(tampered);
    fs.writeFileSync(auditFile, lines.join('\n') + '\n', { mode: 0o600 });
    assert.strictEqual(vault.verifyAudit().ok, false);

    console.log('security-vault: passed');
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
