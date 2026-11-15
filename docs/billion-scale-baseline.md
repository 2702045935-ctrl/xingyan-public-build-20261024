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
- Offline outbox retry, concurrent client-ID deduplication, and restart ordering
- Chat actions and group presence
- Shard coverage, placement, routing, runtime, lease, and message repair
- Shard shadow service and release readiness
- Payment database, concurrent debit, ledger, startup recovery, and real chain
- Upload integrity, favorites sync, and Moment delete persistence

## Next implementation gates

1. Add production-safe shadow verification and mismatch reporting.
2. Run the offline-outbox and reconnect contract on physical devices with
   airplane-mode transitions and forced process termination.
3. Reconcile every shard before any topology cutover.
4. Keep payment settlement disabled until independent ledger reconciliation is
   clean.

## Read-only message audit

`server/tools/message-consistency-audit.js` compares each message JSONL file
with the reliability metadata without calling the writable reliability store.
It uses SQLite `immutable=1`, rejects databases with uncheckpointed WAL/journal
data, and never creates sidecar files beside the source database.

The report checks duplicate and cross-chat message IDs, duplicate client IDs,
sequence gaps and ordering, malformed or undecryptable rows, missing or extra
reliability rows, payload drift, and `chat_sequence.last_seq` mismatches. Issue
rows are deterministically sorted and the report includes a stable fingerprint
that excludes timestamps.

Audit a checkpointed offline snapshot:

```powershell
node server/tools/message-consistency-audit.js `
  --data DATA_DIR `
  --secret SECRET_FILE `
  --source SHARD_ID `
  --out REPORT.json
```

An active WAL must be checkpointed by its owner or copied with the shard's
normal snapshot process. The audit intentionally refuses to guess at
uncheckpointed data and does not repair any mismatch it finds.

Release readiness can require one audit report per shard:

```powershell
node server/tools/shard-release-readiness.js `
  --baseline BASELINE.json `
  --candidate CANDIDATE.json `
  --allowlist ALLOWLIST.json `
  --route-plan ROUTE_PLAN.json `
  --message-audit SHARD_0_AUDIT.json `
  --message-audit SHARD_1_AUDIT.json `
  --require-message-audit `
  --out RELEASE_READINESS.json
```

This gate rejects missing reports, writable or incomplete audits, suppressed
issues, missing fingerprints, and a shard-wide message count that differs from
the candidate inventory.
