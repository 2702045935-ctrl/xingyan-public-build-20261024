#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")
REALTIME = (ROOT / "Sources" / "Realtime.swift").read_text(encoding="utf-8")
LOAD = (ROOT / "server" / "tools" / "chat-capacity-load.js").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("moment red peak verification failed: " + message)


require(
    "function queueMomentRedDot(" in SERVER
    and "action: 'newBatch'" in SERVER
    and "momentUnreadDelta: item.delta" in SERVER
    and "}, 40);" in SERVER,
    "moment red dots must be coalesced into short incremental batches",
)
require(
    "var momentUnreadDelta: Int?" in REALTIME
    and 'obj["momentUnreadDelta"]' in REALTIME
    and "momentsUnread = max(0, momentsUnread + n)" in APP,
    "clients must apply incremental moment unread updates",
)
require(
    "MOMENT_MAX_PER_MINUTE" in SERVER
    and "MOMENT_MAX_PER_DAY" in SERVER
    and "scheduleMomentReplicationSave()" in SERVER
    and "}, 120);" in SERVER,
    "moment persistence must batch replication bookkeeping and keep limits configurable",
)
require(
    "momentAuthors" in LOAD
    and "moment-concurrency" in LOAD
    and "eventCountMismatch" in LOAD
    and "storedMissing" in LOAD,
    "moment peak tests must verify event counts, unread and persisted IDs",
)

print("moment-red-peak: passed")
