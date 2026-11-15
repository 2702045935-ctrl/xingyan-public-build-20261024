# Billion-scale foundation baseline

Date: 2026-11-15

## Production guardrails

- Stable rollback package: `2611150742`
- Stable Git tag: `stable-2611150742`
- Development branch: `codex/million-scale-foundation`
- Main branch and production shards are not changed by this work.
- Message reliability and shard migration remain default-off until shadow
  reconciliation reports zero unexplained differences.

## Required data invariants

1. Every outgoing message has a stable client ID and server message ID.
2. Each conversation has a monotonic sequence.
3. Message persistence, conversation summary updates, and event publication are
   one transaction.
4. Duplicate client IDs return the original message.
5. Device delivery and read cursors are monotonic.
6. Payment ledger records are idempotent and reference a unique payment intent.
7. Chat metadata and payment authority never share mutable JSON state.

## Baseline checks passed

- Message reliability, concurrency, and backfill
- Message cursor/since paging
- Chat actions and group presence
- Shard coverage, placement, routing, runtime, lease, and message repair
- Shard shadow service and release readiness
- Payment database, concurrent debit, ledger, startup recovery, and real chain
- Upload integrity, favorites sync, and Moment delete persistence

## Next implementation gates

1. Add production-safe shadow verification and mismatch reporting.
2. Run client/server duplicate, ordering, reconnect, and offline-outbox tests.
3. Reconcile every shard before any topology cutover.
4. Keep payment settlement disabled until independent ledger reconciliation is
   clean.
