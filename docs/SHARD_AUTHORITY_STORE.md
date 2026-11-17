# Shard authority store

`server/lib/shard-authority-store.js` is the first candidate for a real shard
authority plane. It is intentionally not wired into the live server yet.

## Transaction boundary

One `appendMessage` transaction commits all of the following in the shard's
SQLite database:

1. the message row and stable client-ID idempotency record;
2. the next conversation sequence;
3. the chat summary state;
4. the durable message event for the outbox/event bus.

If any statement fails, all four are rolled back.

## Writer fencing

Every write validates the shard lease before opening the transaction and again
before commit. The second check prevents a writer from committing after another
cell has acquired a newer epoch during the write.

The SQLite transaction and both lease checks are local building blocks. A
production cutover still requires the external lease authority and the
single-writer gateway to be enabled.

## Verification

The store rejects:

- writes without a valid owner lease;
- writes from a stale epoch;
- duplicate client IDs, while returning the original message;
- sequence and chat-summary drift detected by `verify()`.

The first real replacement step is a shadow import of one low-risk shard,
followed by zero-difference reads and a maintenance-window write cutover.

## Snapshot import

The candidate importer walks one shard snapshot, decrypts and validates every
message, sorts by `createdAt + id`, rebuilds a contiguous conversation
sequence, and writes direct-chat messages into the authority transaction store:

```text
node server/tools/import-shard-authority.js \
  --data /path/to/shard \
  --secret /path/to/shard/secret.key \
  --database /path/to/candidate/shard-authority.sqlite3 \
  --shard-id 0 \
  --topology-id server-b-mainline-shards-7 \
  --out /path/to/candidate/import-report.json
```

The importer is direct-chat-only by default. `--all-chats` is reserved for a
later group migration that has its own fanout and notification validation.

After the writer has checkpointed and closed the candidate database, compare
the encrypted source snapshot with the authority database before any cutover:

```text
node server/tools/audit-shard-authority.js \
  --data /path/to/shard \
  --secret /path/to/shard/secret.key \
  --database /path/to/candidate/shard-authority.sqlite3 \
  --out /path/to/candidate/shadow-audit.json
```

The audit checks every chat's message count, identity, sequence, encrypted
payload hash and last-message summary. Missing files, extra chats, sequence
drift and content tampering all fail closed.

## Runtime cutover

The server integration is default-off and direct-chat-only. A single shard can
be cut over with:

```text
SHARD_AUTHORITY_ENABLED=1
SHARD_AUTHORITY_READ=1
SHARD_AUTHORITY_WRITE=1
SHARD_AUTHORITY_DB_FILE=/path/to/shard-authority.sqlite3
SHARD_AUTHORITY_EPOCH=2
SHARD_ID=0
SHARD_TOPOLOGY_ID=server-b-mainline-shards-7
```

With write mode enabled, new direct messages and full transcript rewrites are
committed to the authority database first. The compatibility JSONL remains a
rollback mirror. With read mode enabled, direct-message reads come from the
authority database. Group chats remain on the legacy path until their separate
fanout and cursor migration is complete.
