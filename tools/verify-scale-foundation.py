#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MEMBERS = (ROOT / "server" / "lib" / "group-membership-directory.js").read_text(
    encoding="utf-8"
)
CONNECTIONS = (ROOT / "server" / "lib" / "connection-directory.js").read_text(
    encoding="utf-8"
)
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("scale foundation verification failed: " + message)


require(
    "class GroupMembershipDirectory" in MEMBERS
    and "generations/" in MEMBERS
    and "members-' + String(index).padStart(5, '0')" in MEMBERS
    and "page(chatId, cursor, limit)" in MEMBERS
    and "contains(chatId, userId)" in MEMBERS
    and "group membership shard checksum mismatch" in MEMBERS,
    "group membership must use versioned, checksummed and lazily paged shards",
)
require(
    "class LocalConnectionDirectory" in CONNECTIONS
    and "heartbeat(id)" in CONNECTIONS
    and "sweepExpired()" in CONNECTIONS
    and "gatewaysForUser(userId)" in CONNECTIONS
    and "connection directory capacity exceeded" in CONNECTIONS,
    "connection ownership must expose TTL, multi-device and gateway routing",
)
require(
    "python3 tools/verify-scale-foundation.py" in WORKFLOW
    and "node server/test/scale-foundation.test.js" in WORKFLOW,
    "scale foundation contracts must remain in the build gate",
)

print("scale-foundation: passed")
