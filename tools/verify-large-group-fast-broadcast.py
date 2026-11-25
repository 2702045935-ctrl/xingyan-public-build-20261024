#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")
WS = (ROOT / "server" / "lib" / "ws.js").read_text(encoding="utf-8")
LOAD = (ROOT / "server" / "tools" / "chat-capacity-load.js").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("large-group fast broadcast verification failed: " + message)


require(
    "chat.memberIds.length > 512" in SERVER
    and "const payload = { type: 'message', message: out }" in SERVER
    and "function broadcastCompactChatMessage(chat, payload)" in SERVER
    and "path: '/__shard/chat-broadcast'" in SERVER,
    "large groups must use chat-scoped cross-shard broadcast instead of presence fanout",
)
require(
    "function fanoutGroupSummary(" in SERVER
    and "const groupSummaryCache" in SERVER
    and "summary = built.summary" in SERVER,
    "small large-group fanout must reuse summary variants",
)
require(
    "FANOUT_RELAY_BATCH_SIZE = 512" in SERVER
    and "/__shard/relay-batch" in SERVER
    and "queueFanoutRelay(" in SERVER
    and "flushFanoutRelays(" in SERVER,
    "cross-shard fanout must batch internal requests",
)
require(
    "PRESENCE_GROUP_FANOUT_LIMIT" in SERVER
    and "chat.memberIds.length > PRESENCE_GROUP_FANOUT_LIMIT" in SERVER,
    "large-group presence must not fan out every connection event to all members",
)
require(
    "ws.encodeFrame(0x1, Buffer.from(text, 'utf8'))" in SERVER
    and "ws.sendFrame(socket, encoded.frame)" in SERVER
    and "function sendFrame(socket, frame)" in WS,
    "identical WebSocket payloads must reuse one encoded frame",
)
require(
    "if immediate != nil" in APP
    and "notifyIncomingRow(immediate)" in APP
    and "self.notifyIncomingRow(cid.isEmpty" in APP,
    "message events with a realtime summary must not reload the complete chat list",
)
require(
    "strictDeliverySummary(active)" in LOAD
    and "auditStoredHistory(base, users[0])" in LOAD
    and "arg('p99-budget-ms', '1000')" in LOAD
    and "stage.p99Ms <= p99BudgetMs" in LOAD
    and "orderViolations" in LOAD
    and "clientIdDuplicates" in LOAD,
    "large-data capacity tests must gate duplicates, loss and ordering",
)

print("large-group-fast-broadcast: passed")
