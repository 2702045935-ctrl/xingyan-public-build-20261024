'use strict';

class CanaryGuard {
  constructor(options) {
    const opts = options || {};
    this.maxFailureRatio = Math.max(0, Math.min(1, Number(opts.maxFailureRatio) || 0.05));
    this.maxPending = Math.max(1, Number(opts.maxPending) || 5000);
    this.minSamples = Math.max(1, Number(opts.minSamples) || 20);
    this.paused = false;
    this.reason = '';
    this.samples = 0;
    this.acked = 0;
    this.failed = 0;
    this.pending = 0;
    this.lastAt = 0;
  }

  observe(result, outbox) {
    const row = result || {};
    this.samples += Number(row.scanned) || 0;
    this.acked += Number(row.acked) || 0;
    this.failed += Number(row.failed) || 0;
    const snapshot = outbox && typeof outbox.snapshot === 'function'
      ? outbox.snapshot()
      : {};
    this.pending = Number(snapshot.pending) || 0;
    this.lastAt = Date.now();
    if (this.pending > this.maxPending) {
      this.paused = true;
      this.reason = 'outbox-pending-exceeded';
    } else if (this.samples >= this.minSamples
        && this.failed / Math.max(1, this.samples) > this.maxFailureRatio) {
      this.paused = true;
      this.reason = 'gateway-failure-ratio-exceeded';
    }
    return this.snapshot();
  }

  resume() {
    this.paused = false;
    this.reason = '';
    this.samples = 0;
    this.acked = 0;
    this.failed = 0;
    return this.snapshot();
  }

  snapshot() {
    return {
      paused: this.paused,
      reason: this.reason,
      samples: this.samples,
      acked: this.acked,
      failed: this.failed,
      pending: this.pending,
      failureRatio: this.samples ? this.failed / this.samples : 0,
      maxFailureRatio: this.maxFailureRatio,
      maxPending: this.maxPending,
      lastAt: this.lastAt
    };
  }
}

module.exports = { CanaryGuard };
