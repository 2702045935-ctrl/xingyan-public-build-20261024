# Scale Foundation V1

This layer prepares the existing JSON/file implementation for later distributed
storage without changing the production chat path in the same release.

## Group membership directory

`server/lib/group-membership-directory.js` separates group membership from chat
metadata.

- Every update creates an immutable generation.
- `current.json` is switched atomically after the generation is durable.
- Members are sorted and split into file shards, 1,000 members by default.
- Group counts come from the pointer or manifest and do not read all members.
- Member pages read only the shards covered by the requested range.
- Each shard and the full member set carry SHA-256 checksums.
- Large-group fanout may materialize one active group, never every group.

This removes the single `chats.json` string-size failure for a 10,000-member
group and gives migration code a safe target. The server does not switch to this
directory until the physical-shard and shadow-reconciliation gates are complete.

Shadow migration is read-only by default:

```powershell
node server/tools/group-membership-shadow-migration.js `
  --chats=DATA_DIR/chats.json `
  --root=SHADOW_ROOT `
  --out=SHADOW_REPORT.json
```

Only an explicit `--apply` writes the isolated shadow directory. Every migrated
group is verified by member count, full member digest, first-page round trip and
generation manifest before the report can pass.

## Connection directory

`server/lib/connection-directory.js` defines the connection ownership contract
that must replace the process-local `connections` map.

- A connection has a stable ID, user, gateway, region, shard and epoch.
- Heartbeats extend a bounded TTL.
- Multiple devices and gateways are indexed per user.
- Expired records are removed without leaving stale user or gateway indexes.
- Capacity is explicitly bounded.

The local implementation is for contract tests. A later production adapter must
provide the same behavior through a distributed, sharded directory and fencing
epochs.

## Integration gates

1. Migrate group membership in shadow mode and compare every page and count.
2. Route member APIs to the directory while chat metadata remains compatible.
3. Only then remove inline `memberIds` from large-group persistence.
4. Add a distributed connection-directory adapter behind the local interface.
5. Dual-read and dual-write connection ownership before removing the local map.
6. Require production lease fencing and stale-owner rejection before cutover.
