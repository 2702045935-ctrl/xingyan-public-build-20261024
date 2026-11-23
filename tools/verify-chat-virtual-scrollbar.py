#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
LIST = (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8")
FIXTURE = (ROOT / "Sources" / "MessageStressFixture.swift").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat virtual scrollbar verification failed: " + message)


require(
    "virtualHistoryPosition: nativeHistoryPosition" in CHAT
    and "private func nativeHistoryPosition" in CHAT
    and "let seq = message.seq" in CHAT
    and "Double(seq - 1) / Double(total - 1)" in CHAT,
    "the chat scrollbar must map visible rows onto the full sequence axis",
)
require(
    "private func nativeHistoryPosition" in CHAT
    and "MessageStressFixture.messageCount(for: chat.id)" in CHAT
    and "total = newestAvailableSeq" in CHAT,
    "both synthetic and server-backed histories must retain a stable axis",
)
require(
    "static func messageCount(for chatId: String) -> Int" in FIXTURE
    and "return groupSize(group)" in FIXTURE,
    "the stress fixture must expose the exact per-chat history length",
)
require(
    "virtualHistoryPosition: ((Item) -> Double?)? = nil" in LIST
    and "collection.showsVerticalScrollIndicator = false" in LIST
    and "private final class NativeVirtualScrollIndicator" in LIST,
    "windowed histories must replace the content-size-bound system thumb",
)
require(
    "let minimumHeight: CGFloat = 36" in LIST
    and "topProgress * travel" in LIST
    and "setScrolling(active)" in LIST
    and "isUserInteractionEnabled = false" in LIST,
    "the virtual thumb must remain visible, low-cost and non-blocking",
)
require(
    "values.append(min(1, max(0, value)))" in LIST
    and "indicator.update(top: top, bottom: bottom)" in LIST,
    "the custom indicator must update from actual visible message positions",
)

print("chat-virtual-scrollbar: passed")
