#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
NATIVE = (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8")
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat-history-coverage verification failed: " + message)


require(
    "const before = Number(query.get('before')) || Number.MAX_SAFE_INTEGER;" in SERVER
    and "m.seq < before" in SERVER
    and "messagesSince(chatId:" in CHAT
    and "all: true" in CHAT,
    "server history must remain sequence based in both directions",
)
require(
    "private func loadOlder() async" in CHAT
    and "private func loadNewer() async" in CHAT
    and "installHistoryWindow(merged, evictingNewestIntoOlder: true)" in CHAT
    and "installHistoryWindow(merged, evictingNewestIntoOlder: false)" in CHAT
    and "Array(rows.dropLast(overflow))" in CHAT
    and "Array(rows.dropFirst(overflow))" in CHAT,
    "older and newer pages must rotate a bounded active window",
)
require(
    "prefetchDataSource = context.coordinator" in NATIVE
    and "prefetchItemsAt indexPaths" in NATIVE
    and "requestOlderPageFromSystemPrefetch()" in CHAT
    and "requestNewerPageFromSystemPrefetch()" in CHAT
    and "olderNextCursor" in CHAT
    and "newerNextCursor" in CHAT
    and "rotateOlderRunway(with: evicted)" in CHAT
    and "rotateNewerRunway(with: evicted)" in CHAT,
    "system prefetch must drive both directions while evicted pages remain reusable",
)
require(
    "historyRuntime.oldestLoadedSeq = oldest" in CHAT
    and "historyRuntime.newestLoadedSeq = newest" in CHAT
    and "hasOlder = more" in CHAT
    and "hasNewerMessages" in CHAT,
    "window edges must drive both history availability flags after every rotation",
)
require(
    "private let historyWindowPages = 10" in CHAT
    and "private let historyPrefetchPages = 3" in CHAT
    and "ChatScrollHandle.shared.prepareForPrepend()" in CHAT,
    "complete history must remain reachable without materializing the entire chat",
)

print("chat-history-coverage: passed")
