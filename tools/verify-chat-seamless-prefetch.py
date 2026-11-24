#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
NATIVE = (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8")
MODEL = (ROOT / "tools" / "verify-chat-windowed-history-model.py").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat seamless prefetch verification failed: " + message)


require(
    "private let historyPageSize = 120" in CHAT
    and "private let historyPrefetchPages = 3" in CHAT
    and "private let historyWindowPages = 10" in CHAT
    and "historyPageSize * historyPrefetchPages" in CHAT
    and "historyPageSize * historyWindowPages" in CHAT,
    "chat must use 120-row pages, a 360-row runway and a 1200-row active window",
)
require(
    "MessageStressFixture.isActive ? stressMessageWindow : historyWindowLimit" in CHAT
    and "stressMessageWindow : 50_000" not in CHAT,
    "ordinary chat history must not grow to the legacy fifty-thousand-row window",
)
require(
    "Array(merged.prefix(maxMessageWindow))" in CHAT
    and "Array(merged.suffix(maxMessageWindow))" in CHAT,
    "older and newer traversal must rotate opposite edges of the active window",
)
require(
    "private let historyScrollChunkSize = 48" in CHAT
    and "let consumeLimit = ChatScrollHandle.shared.moving" in CHAT
    and CHAT.count("historyScrollChunkSize") >= 3,
    "moving prefetch consumption must be split into 48-row native updates",
)
require(
    "if olderPrefetch.isEmpty, let pending = olderPrefetchTask" in CHAT
    and "await pending.value" in CHAT
    and "private func scheduleOlderPrefetch(" in CHAT
    and "private func takeOlderPrefetch()" in CHAT
    and "private func scheduleNewerPrefetch(" in CHAT
    and "private func takeNewerPrefetch()" in CHAT,
    "both history directions must retain reusable prefetch caches",
)
require(
    "olderPrefetch.count < target" in CHAT
    and "newerPrefetch.count < target" in CHAT
    and "limit: historyPageSize" in CHAT
    and "let requestLimit = min(" in CHAT
    and "limit: requestLimit" in CHAT
    and "Array(rows.suffix(count))" in CHAT
    and "Array(rows.prefix(count))" in CHAT,
    "prefetch must fill a 360-row cache in one bounded request while consuming one page",
)
require(
    "initialCacheReady = true\n            // Start the hidden history runway" in CHAT
    and "rebuildIndex()\n            scheduleOlderPrefetch()" in CHAT
    and "scroll.bounds.height * 12.0" in CHAT,
    "cached chats must arm the runway before the latest-page network refresh",
)
require(
    "private func invalidateOlderPrefetch()" in CHAT
    and "private func invalidateNewerPrefetch()" in CHAT
    and "invalidateNewerPrefetch()" in CHAT
    and "invalidateOlderPrefetch()" in CHAT
    and "scheduleOlderPrefetch(\n                before: bounded.lazy.compactMap" in CHAT,
    "changing direction must invalidate stale caches and rebuild the opposite runway",
)
require(
    "onPrefetchStart:" in NATIVE
    and "onPrefetchEnd:" in NATIVE
    and "prefetchStartArmed = true" in NATIVE
    and "prefetchEndArmed = true" in NATIVE
    and "updateDataPrefetchEdges(first: first, last: last)" in NATIVE,
    "native collection prefetch callbacks must rearm on every physical gesture",
)
require(
    "deferredMeasureIDs" in NATIVE
    and "guard !deferredMeasureQueued,\n                  !deferredMeasureIDs.isEmpty,\n                  !isMoving else { return }" in NATIVE
    and "scheduleVirtualScrollIndicatorUpdate()" in NATIVE,
    "scroll-time prefetch must keep height and indicator work off the per-frame hot path",
)
require(
    "private func recoverVisibleWindowIfNeeded" in NATIVE
    and "collection.scrollToItem(" in NATIVE
    and "collection.collectionViewLayout.invalidateLayout()" in NATIVE,
    "native history rotation must recover from an empty visible window",
)
require(
    "private func restoreVisibleAnchor(" in NATIVE
    and "target.y = min(max(target.y + layoutDelta, minimumY), maximumY)" in NATIVE
    and "preferredID: Item.ID? = nil" in NATIVE
    and "attributes.frame.minY\n                - (previousOffset.y + anchor.delta)" in NATIVE,
    "deferred native inserts must preserve in-flight pan displacement",
)
require(
    '"randomOperations": 100_000' in MODEL
    and "WINDOW_LIMIT = PAGE_SIZE * WINDOW_PAGES" in MODEL
    and "RUNWAY_LIMIT = PAGE_SIZE * RUNWAY_PAGES" in MODEL,
    "the two-way history model must retain its long random-operation regression",
)

print("chat-seamless-prefetch: passed")
