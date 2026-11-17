#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function loadSecurityVault() {
  const modulePath = arg('vault-module');
  return require(modulePath || '../../server/lib/security-vault').createSecurityVault;
}

const createSecurityVault = loadSecurityVault();

function readSecret(file) {
  return fs.readFileSync(file, 'utf8').trim();
}

function readKeyring(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function vaultFor(dataDir, secretFile, keyringFile) {
  const vault = createSecurityVault({
    dataDir,
    rootMaterial: readSecret(secretFile)
  });
  vault.keyring = readKeyring(keyringFile);
  vault.dataKeyCache.clear();
  return vault;
}

function canOpen(vault, chatId, envelope) {
  try {
    vault.openJson('message', chatId, envelope, null);
    return true;
  } catch (_) {
    return false;
  }
}

function atomicWrite(file, text) {
  const temporary = file + '.' + process.pid + '.' + Date.now() + '.keymigrate';
  const descriptor = fs.openSync(temporary, 'w', 0o600);
  try {
    fs.writeFileSync(descriptor, text, 'utf8');
    fs.fsyncSync(descriptor);
  } finally {
    fs.closeSync(descriptor);
  }
  fs.renameSync(temporary, file);
}

function migrateDataDir(options) {
  const dataDir = path.resolve(options.dataDir);
  const messagesDir = path.join(dataDir, 'messages');
  if (!fs.existsSync(messagesDir)) {
    throw new Error('messages directory does not exist: ' + messagesDir);
  }
  const current = vaultFor(dataDir, options.currentSecret, options.currentKeyring);
  const target = vaultFor(dataDir, options.targetSecret, options.targetKeyring);
  const backupDir = path.resolve(options.backupDir);
  fs.mkdirSync(backupDir, { recursive: true, mode: 0o700 });

  const report = {
    dataDir,
    files: 0,
    encryptedMessages: 0,
    alreadyTarget: 0,
    migrated: 0,
    changedFiles: [],
    backupDir
  };

  for (const name of fs.readdirSync(messagesDir).sort()) {
    if (!name.endsWith('.jsonl')) continue;
    report.files += 1;
    const file = path.join(messagesDir, name);
    const chatId = name.slice(0, -6);
    const source = fs.readFileSync(file, 'utf8');
    const lines = source.split(/\r?\n/);
    let changed = false;
    const output = lines.map((line) => {
      if (!line) return line;
      const envelope = JSON.parse(line);
      if (!envelope || envelope.e !== 1 || !envelope.kv) return line;
      report.encryptedMessages += 1;
      if (canOpen(target, chatId, envelope)) {
        report.alreadyTarget += 1;
        return line;
      }
      if (!canOpen(current, chatId, envelope)) {
        throw new Error('message cannot be opened by current or target key domain: '
          + path.join('messages', name));
      }
      const migrated = target.sealJson('message', chatId, current.openJson(
        'message',
        chatId,
        envelope,
        null
      ));
      report.migrated += 1;
      changed = true;
      return JSON.stringify(migrated);
    });
    if (!changed) continue;
    fs.copyFileSync(file, path.join(backupDir, name), fs.constants.COPYFILE_EXCL);
    atomicWrite(file, output.join('\n'));
    report.changedFiles.push(name);
  }
  return report;
}

function main() {
  const report = migrateDataDir({
    dataDir: arg('data'),
    currentSecret: arg('current-secret'),
    currentKeyring: arg('current-keyring'),
    targetSecret: arg('target-secret'),
    targetKeyring: arg('target-keyring'),
    backupDir: arg('backup-dir')
  });
  process.stdout.write(JSON.stringify(report, null, 2) + '\n');
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    console.error(error.stack || error);
    process.exitCode = 1;
  }
}

module.exports = { migrateDataDir };
