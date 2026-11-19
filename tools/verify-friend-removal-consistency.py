#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
TEST = (ROOT / "server" / "test" / "multishard-state.test.js").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("friend-removal consistency verification failed: " + message)


require(
    "function friendIds(userId)" in SERVER
    and "!friendPairWasRemoved(f.fromId, f.toId)" in SERVER,
    "accepted friend lists must exclude tombstoned pairs even on a stale shard",
)
require(
    "async function broadcastFriendRemovalToPeers(a, b, deleted)" in SERVER
    and "'/__shard/friend-removal'" in SERVER,
    "friend tombstones must have a signed cross-shard replication path",
)
require(
    "broadcastFriendRemovalToPeers(a, b, true).catch" in SERVER
    and "broadcastFriendRemovalToPeers(a, b, false).catch" in SERVER,
    "delete and re-add must replicate both tombstone writes and clears",
)
require(
    "await broadcastFriendRemovalToPeers(" in SERVER
    and "friendship.toId,\n      true" in SERVER,
    "relationship deletion must await tombstone replication before success",
)
require(
    "markFriendRemoved(a, b, false)" in SERVER
    and "clearFriendRemoved(a, b, false)" in SERVER,
    "the internal replication endpoint must not recursively rebroadcast",
)
require(
    "markFriendRemoved(user.id, target.id, false)" in SERVER,
    "the remove route must use the awaited replication performed by the relationship owner",
)
require(
    "deleted friend must not bypass send guard on another shard" in TEST,
    "cross-shard regression must attempt a send after deletion",
)
require(
    "node server/test/multishard-state.test.js" in WORKFLOW,
    "cross-shard friend deletion regression must run in the iOS gate",
)

print("friend-removal-consistency: passed")
