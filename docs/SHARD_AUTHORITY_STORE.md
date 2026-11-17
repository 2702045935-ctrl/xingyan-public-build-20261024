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
