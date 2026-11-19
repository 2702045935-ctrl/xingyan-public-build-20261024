#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
NATIVE = (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat seamless prefetch verification failed: " + message)


require(
    "private var olderPrefetch: [Message]" in CHAT
    and "private func scheduleOlderPrefetch()" in CHAT
    and "private func takeOlderPrefetch(limit: Int)" in CHAT,
    "older history must stay prefetched ahead of the viewport",
)
require(
    "if olderPrefetch.count < pageTarget, let pending = olderPrefetchTask" in CHAT
    and "await pending.value" in CHAT,
    "foreground paging must reuse an in-flight prefetch instead of waiting twice",
)
require(
    "if y < 4200" in CHAT,
    "large chats must prefetch before the user reaches the first row",
)
require(
    "private var oldestHistorySeq: Int" in CHAT
    and "messages.lazy.compactMap(\\.seq).first(where: { $0 > 0 })" in CHAT
    and CHAT.count("oldestHistorySeq") >= 4
    and "let seq = messages.first?.seq" not in CHAT,
    "history cursors must skip leading system rows that have no sequence",
)
require(
    "let pageTarget = isGroup ? 300 : 200" in CHAT
    and "let targetDepth = pageTarget" in CHAT
    and "buffer.insert(contentsOf: rows, at: 0)" in CHAT
    and "let maxPages = isGroup ? 2 : 3" in CHAT,
    "deep-group prefetch must keep the same 300-row runway as the beginning",
)
require(
    "prependAnchor =" in NATIVE
    and "attributes.frame.minY - anchor.delta" in NATIVE
    and "clearPendingPrepend()" in NATIVE,
    "native prepend must restore the visible row before the next frame",
)
require(
    "onApplyCompleted" in NATIVE
    and "nativeHistoryApplyPending" in CHAT,
    "automatic pinning must stay blocked until native prepend commit completes",
)

print("chat-seamless-prefetch: passed")
