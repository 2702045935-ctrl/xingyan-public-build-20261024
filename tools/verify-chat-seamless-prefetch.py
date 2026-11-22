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
    and "private func scheduleOlderPrefetch(" in CHAT
    and "private func takeOlderPrefetch()" in CHAT,
    "older history must stay prefetched ahead of the viewport",
)
require(
    "if olderPrefetch.isEmpty, let pending = olderPrefetchTask" in CHAT
    and "await pending.value" in CHAT,
    "foreground paging must reuse an in-flight prefetch instead of waiting twice",
)
require(
    "guard isGroup, y < 4200" in CHAT,
    "B2611191645 chat prefetch must use the fixed 4200-point trigger",
)
require(
    "ChatScrollHandle.shared.moving else { return }" in CHAT
    and "if isGroup { autoLoadOlder() }" not in CHAT,
    "automatic history paging must be driven by the user scroll runway",
)
require(
    "ScrollGate.shared.setScrolling(false)" in CHAT
    and "let y = ChatScrollHandle.shared.scroll?.contentOffset.y" in CHAT
    and "y < 4200" in CHAT,
    "history runway must also be consumed after deceleration ends",
)
require(
    "private var oldestHistorySeq: Int" in CHAT
    and "messages.lazy.compactMap(\\.seq).first(where: { $0 > 0 })" in CHAT
    and CHAT.count("oldestHistorySeq") >= 4
    and "let seq = messages.first?.seq" not in CHAT,
    "history cursors must skip leading system rows that have no sequence",
)
require(
    "let target = isGroup ? 150 : 200" in CHAT
    and "let canContinue = explicitMore ?? hasOlder" in CHAT
    and "guard canContinue, olderPrefetch.isEmpty, olderPrefetchTask == nil" in CHAT
    and "olderPrefetch = visibleMessages(page.messages)" in CHAT
    and "before: seq" in CHAT
    and "let maxPages = isGroup ? 1 : 2" in CHAT,
    "chat prefetch must keep a bounded single-page runway",
)
require(
    "scheduleOlderPrefetch(before: nextCursor" in CHAT
    and "knownIds: Set(bounded.map(\\.id))" in CHAT
    and "continues: more" in CHAT,
    "each consumed history page must enqueue exactly one fresh prefetch page",
)
require(
    "prependAnchor =" in NATIVE
    and "attributes.frame.minY - anchor.delta" in NATIVE
    and "clearPendingPrepend()" in NATIVE,
    "native prepend must restore the visible row before the next frame",
)
require(
    "ChatScrollHandle.shared.prepareForPrepend()" in CHAT
    and "_ = ChatScrollHandle.shared.compensatePendingPrepend()" in NATIVE,
    "B2611191645 history prepends must use the original atomic compensation path",
)

print("chat-seamless-prefetch: passed")
