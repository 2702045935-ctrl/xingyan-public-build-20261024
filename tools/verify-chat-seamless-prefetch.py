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
    "installHistoryWindow(merged, evictingNewestIntoOlder: true)" in CHAT
    and "installHistoryWindow(merged, evictingNewestIntoOlder: false)" in CHAT
    and "Array(rows.dropLast(overflow))" in CHAT
    and "Array(rows.dropFirst(overflow))" in CHAT,
    "older and newer traversal must rotate opposite edges in one indexed commit",
)
require(
    "private let historyScrollChunkSize = 48" in CHAT
    and "let consumeLimit = ChatScrollHandle.shared.moving" in CHAT
    and CHAT.count("historyScrollChunkSize") >= 3,
    "moving prefetch consumption must be split into 48-row native updates",
)
require(
    "prefetchDataSource = context.coordinator" in NATIVE
    and "collectionView(_ collectionView: UICollectionView,\n                            prefetchItemsAt indexPaths: [IndexPath])" in NATIVE
    and "requestOlderPageFromSystemPrefetch()" in CHAT
    and "requestNewerPageFromSystemPrefetch()" in CHAT,
    "UICollectionViewDataSourcePrefetching must request both history directions",
)
require(
    "let target = historyPageSize" in CHAT
    and "let maxPages = 1" in CHAT
    and "limit: target" in CHAT
    and "scheduleOlderPrefetch(" not in CHAT
    and "scheduleNewerPrefetch(" not in CHAT,
    "a system prefetch callback must request exactly one foreground history page",
)
require(
    "initialCacheReady = true" in CHAT
    and "The collection's prefetch data source owns page timing" in CHAT
    and "onScrollOffset: nil" in CHAT
    and "scroll.bounds.height * 12.0" not in CHAT,
    "cached chats must wait for the collection's system prefetch timing",
)
require(
    "installHistoryWindow(merged, evictingNewestIntoOlder: true)" in CHAT
    and "installHistoryWindow(merged, evictingNewestIntoOlder: false)" in CHAT
    and "rotateNewerRunway(with: evicted)" in CHAT
    and "rotateOlderRunway(with: evicted)" in CHAT
    and "newerPrefetch = Array(combined.prefix(target))" in CHAT
    and "olderPrefetch = Array(combined.suffix(target))" in CHAT,
    "changing direction must rotate the opposite in-memory runway",
)
require(
    "onPrefetchStart:" in NATIVE
    and "onPrefetchEnd:" in NATIVE
    and "prefetchStartArmed = true" in NATIVE
    and "prefetchEndArmed = true" in NATIVE
    and "updateDataPrefetchEdges(" in NATIVE
    and "prefetchItemsAt indexPaths" in NATIVE
    and "onScrollOffset: nil" in CHAT,
    "native collection callbacks must be the sole chat prefetch trigger",
)
require(
    "deferredMeasureIDs" in NATIVE
    and "guard !deferredMeasureQueued,\n                  !deferredMeasureIDs.isEmpty,\n                  !isMoving else { return }" in NATIVE
    and "scheduleVirtualScrollIndicatorUpdate()" in NATIVE,
    "scroll-time prefetch must keep height and indicator work off the per-frame hot path",
)
require(
    "let revision: Int" in NATIVE
    and "context.coordinator.itemsRevision != revision" in NATIVE
    and "historyRuntime.revision &+= 1" in CHAT
    and "revision: nativeMessageListRevision" in CHAT,
    "scroll state changes must not diff the full history window unless message data changed",
)
require(
    "let removedFromWindow = Set(order).subtracting(nextIDs)" in NATIVE
    and "heights.removeValue(forKey: id)" in NATIVE
    and "warmHosts.removeValue(forKey: id)" in NATIVE,
    "rotating the active history window must evict obsolete row measurements and hosts",
)
require(
    "rotateNewerRunway(with: evicted)" in CHAT
    and "rotateOlderRunway(with: evicted)" in CHAT
    and "newerPrefetch = Array(combined.prefix(target))" in CHAT
    and "olderPrefetch = Array(combined.suffix(target))" in CHAT,
    "an evicted history edge must become the opposite in-memory runway",
)
require(
    "private func mergeVisibleMessages(" in CHAT
    and "while ai < a.count, bi < b.count" in CHAT
    and "return deduplicatedVisibleMessages(merged)" in CHAT,
    "history page consumption must merge ordered rows linearly",
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
    "private enum NativeStaticCellConstraints" in NATIVE
    and "view.translatesAutoresizingMaskIntoConstraints = false" in NATIVE
    and "view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)" in NATIVE,
    "native collection cells must let Auto Layout position hosted row content",
)
require(
    '"randomOperations": 100_000' in MODEL
    and "WINDOW_LIMIT = PAGE_SIZE * WINDOW_PAGES" in MODEL
    and "RUNWAY_LIMIT = PAGE_SIZE * RUNWAY_PAGES" in MODEL,
    "the two-way history model must retain its long random-operation regression",
)

print("chat-seamless-prefetch: passed")
