'use strict';

const fs = require('fs');
const path = require('path');

const SHANGHAI_OFFSET_MS = 8 * 3600 * 1000;

function shanghaiDate(date, offsetDays) {
  const shifted = new Date(date.getTime() + SHANGHAI_OFFSET_MS
    + (Number(offsetDays) || 0) * 86400000);
  return shifted.toISOString().slice(0, 10);
}

class PaymentSettlementScheduler {
  constructor(options) {
    const opts = options || {};
    this.provider = opts.provider || null;
    this.database = opts.database || null;
    this.file = String(opts.file || '');
    this.hour = Math.max(0, Math.min(23, Number(opts.hour) || 3));
    this.minute = Math.max(0, Math.min(59, Number(opts.minute) || 30));
    this.retryMs = Math.max(60000, Number(opts.retryMs) || 30 * 60 * 1000);
    this.now = typeof opts.now === 'function' ? opts.now : () => new Date();
    this.setTimer = typeof opts.setTimeout === 'function' ? opts.setTimeout : setTimeout;
    this.clearTimer = typeof opts.clearTimeout === 'function' ? opts.clearTimeout : clearTimeout;
    this.timer = null;
    this.running = false;
    this.state = { version: 1, runs: [] };
    this.load();
  }

  load() {
    if (!this.file || !fs.existsSync(this.file)) return;
    try {
      const value = JSON.parse(fs.readFileSync(this.file, 'utf8'));
      if (value && value.version === 1 && Array.isArray(value.runs)) {
        this.state = value;
      }
    } catch (_) {
      this.state = { version: 1, runs: [] };
    }
  }

  persist() {
    if (!this.file) return;
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    const temp = this.file + '.tmp';
    fs.writeFileSync(temp, JSON.stringify(this.state), 'utf8');
    fs.renameSync(temp, this.file);
  }

  start() {
    if (this.timer || !this.provider || !this.database) return;
    const yesterday = shanghaiDate(this.now(), -1);
    const caughtUp = this.state.runs.some(
      (row) => row.date === yesterday && row.status === 'succeeded'
    );
    this.schedule(caughtUp ? this.delayUntilNextRun() : 2000);
  }

  stop() {
    if (this.timer) this.clearTimer(this.timer);
    this.timer = null;
  }

  delayUntilNextRun() {
    const now = this.now();
    const shanghaiNow = new Date(now.getTime() + SHANGHAI_OFFSET_MS);
    const next = new Date(Date.UTC(
      shanghaiNow.getUTCFullYear(),
      shanghaiNow.getUTCMonth(),
      shanghaiNow.getUTCDate(),
      this.hour,
      this.minute,
      0
    ));
    let localDelay = next.getTime() - shanghaiNow.getTime();
    if (localDelay <= 0) localDelay += 86400000;
    return localDelay;
  }

  schedule(delayMs) {
    if (this.timer) this.clearTimer(this.timer);
    this.timer = this.setTimer(async () => {
      this.timer = null;
      let delay = this.delayUntilNextRun();
      try {
        await this.run(shanghaiDate(this.now(), -1));
      } catch (_) {
        delay = this.retryMs;
      } finally {
        if (this.timer === null) this.schedule(delay);
      }
    }, Math.max(1000, Number(delayMs) || 1000));
    if (this.timer && this.timer.unref) this.timer.unref();
  }

  async run(date) {
    const targetDate = String(date || '');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(targetDate)) {
      throw new Error('settlement date must be YYYY-MM-DD');
    }
    if (!this.provider || !this.database) {
      throw new Error('payment provider or database is unavailable');
    }
    if (!this.provider.ready()) {
      throw new Error('payment provider is not ready');
    }
    const previous = this.state.runs.find(
      (row) => row.date === targetDate && row.status === 'succeeded'
    );
    if (previous && previous.duplicateGuard === true) {
      return { duplicate: true, run: previous };
    }
    if (this.running) throw new Error('settlement reconciliation is already running');
    this.running = true;
    const startedAt = this.now().toISOString();
    try {
      const lines = await this.provider.settlementReport(targetDate);
      const result = this.database.reconcileProviderSettlement(
        this.provider.name,
        targetDate,
        lines
      );
      const run = {
        date: targetDate,
        provider: this.provider.name,
        status: 'succeeded',
        duplicateGuard: true,
        startedAt,
        finishedAt: this.now().toISOString(),
        providerLines: Number(result.providerLines) || 0,
        localLines: Number(result.localLines) || 0,
        mismatches: Array.isArray(result.mismatches) ? result.mismatches.length : 0
      };
      this.state.runs.unshift(run);
      this.state.runs = this.state.runs.slice(0, 120);
      this.persist();
      return { duplicate: false, run, result };
    } catch (error) {
      this.state.runs.unshift({
        date: targetDate,
        provider: this.provider.name,
        status: 'failed',
        startedAt,
        finishedAt: this.now().toISOString(),
        error: String(error && error.message || error).slice(0, 500)
      });
      this.state.runs = this.state.runs.slice(0, 120);
      this.persist();
      throw error;
    } finally {
      this.running = false;
    }
  }

  latest() {
    return this.state.runs[0] || null;
  }
}

module.exports = {
  PaymentSettlementScheduler,
  shanghaiDate
};
