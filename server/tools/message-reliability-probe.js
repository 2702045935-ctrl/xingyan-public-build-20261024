#!/usr/bin/env node
'use strict';

const fs = require('fs');
const crypto = require('crypto');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { DatabaseSync } = require('node:sqlite');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function runWorker(databaseFile, worker, count) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [
      path.join(__dirname, 'message-reliability-probe-worker.js'),
      databaseFile,
      String(worker),
      String(count)
    ], {
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });
    const stdout = [];
    const stderr = [];
    child.stdout.on('data', (chunk) => stdout.push(chunk));
    child.stderr.on('data', (chunk) => stderr.push(chunk));
    child.on('error', reject);
    child.on('exit', (code) => {
      if (code !== 0) {
        reject(new Error('probe worker failed:\n'
          + Buffer.concat(stderr).toString('utf8')));
        return;
      }
      try {
        resolve(JSON.parse(Buffer.concat(stdout).toString('utf8')));
      } catch (error) {
        reject(error);
      }
    });
  });
}

async function main() {
  const workers = Math.max(1, Math.min(64, Math.floor(Number(arg('workers', '8')) || 8)));
  const perWorker = Math.max(1, Math.min(
    100000,
    Math.floor(Number(arg('per-worker', '500')) || 500)
  ));
  const expected = workers * perWorker;
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-reliability-probe-'));
  const databaseFile = path.join(root, 'message-reliability.sqlite3');
  try {
    const startedAt = Date.now();
    const results = await Promise.all(
      Array.from({ length: workers }, (_, index) =>
        runWorker(databaseFile, index, perWorker)
      )
    );
    const elapsedMs = Math.max(1, Date.now() - startedAt);
    const sequences = results.flatMap((result) => result.sequences)
      .sort((left, right) => left - right);
    const contiguous = sequences.length === expected
      && sequences.every((seq, index) => seq === index + 1);

    const database = new DatabaseSync(databaseFile, { readOnly: true });
    let messages;
    let events;
    let maxSeq;
    try {
      messages = Number(database.prepare(`
        SELECT COUNT(*) AS count FROM reliable_messages
      `).get().count);
      events = Number(database.prepare(`
        SELECT COUNT(*) AS count FROM message_events
        WHERE type = 'message.created'
      `).get().count);
      maxSeq = Number(database.prepare(`
        SELECT MAX(last_seq) AS seq FROM chat_sequence
      `).get().seq);
    } finally {
      database.close();
    }
    const report = {
      version: 1,
      generatedAt: new Date().toISOString(),
      scope: 'system-temporary-directory',
      workers,
      perWorker,
      expectedMessages: expected,
      elapsedMs,
      throughputPerSecond: Math.round(expected * 1000 / elapsedMs),
      sequenceCount: sequences.length,
      firstSequence: sequences.length ? sequences[0] : 0,
      lastSequence: sequences.length ? sequences[sequences.length - 1] : 0,
      sequenceDigest: crypto.createHash('sha256')
        .update(sequences.join(','))
        .digest('hex'),
      contiguous,
      messages,
      events,
      maxSeq,
      databaseBytes: fs.statSync(databaseFile).size,
      ok: contiguous
        && messages === expected
        && events === expected
        && maxSeq === expected
    };
    if (process.argv.includes('--include-sequences')) report.sequences = sequences;
    const text = JSON.stringify(report, null, 2);
    const out = arg('out');
    if (out) {
      const file = path.resolve(out);
      fs.mkdirSync(path.dirname(file), { recursive: true });
      const temporary = file + '.' + process.pid + '.tmp';
      fs.writeFileSync(temporary, text, 'utf8');
      fs.renameSync(temporary, file);
      console.log(JSON.stringify({
        ok: report.ok,
        workers: report.workers,
        messages: expected,
        elapsedMs: report.elapsedMs,
        throughputPerSecond: report.throughputPerSecond,
        out: file
      }, null, 2));
    } else {
      process.stdout.write(text);
    }
    if (!report.ok) process.exitCode = 2;
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.stack || error);
    process.exitCode = 1;
  });
}

module.exports = { main };
