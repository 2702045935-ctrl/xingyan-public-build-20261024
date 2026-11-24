'use strict';

class FanoutDispatcher {
  constructor(options) {
    const opts = options || {};
    if (!opts.outbox || !opts.bus) throw new Error('outbox and bus are required');
    this.outbox = opts.outbox;
    this.bus = opts.bus;
    this.maxBackoffMs = Math.max(1000, Number(opts.maxBackoffMs) || 60_000);
    this.now = typeof opts.now === 'function' ? opts.now : Date.now;
  }

  enqueue(input) {
    return this.outbox.enqueue(input);
  }

  backoff(attempts) {
    return Math.min(this.maxBackoffMs, 1000 * Math.pow(2, Math.max(0, attempts - 1)));
  }

  async flush(options) {
    const opts = options || {};
    const rows = this.outbox.ready(opts.limit || 50);
    const result = {
      scanned: rows.length,
      acked: 0,
      failed: 0,
      skipped: 0,
      delivered: 0
    };
    for (const row of rows) {
      const attempt = this.outbox.attempt(row.id);
      if (!attempt) {
        result.skipped += 1;
        continue;
      }
      try {
        const sent = await this.bus.publish({
          publishId: attempt.publishId,
          nodes: attempt.nodes,
          payload: attempt.payload,
          dryRun: opts.dryRun === true
        });
        result.delivered += Number(sent.delivered) || 0;
        if (sent.ok) {
          this.outbox.ack(row.id);
          result.acked += 1;
        } else {
          this.outbox.fail(row.id,
            sent.results.filter((item) => !item.ok).map((item) => item.error).join(','),
            this.now() + this.backoff(attempt.attempts));
          result.failed += 1;
        }
      } catch (error) {
        this.outbox.fail(row.id, String(error && error.message || error),
          this.now() + this.backoff(attempt.attempts));
        result.failed += 1;
      }
    }
    return result;
  }
}

module.exports = { FanoutDispatcher };
