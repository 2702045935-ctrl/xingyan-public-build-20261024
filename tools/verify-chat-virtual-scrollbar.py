#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
LIST = (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("native chat scrollbar verification failed: " + message)


require(
    "virtualHistoryPosition: nil" in CHAT,
    "chat must use the native scroll indicator instead of a virtual thumb",
)
require(
    "collection.showsVerticalScrollIndicator = true" in LIST
    and "collection.isPrefetchingEnabled = true" in LIST
    and "collection.prefetchDataSource = context.coordinator" in LIST,
    "message history must use UICollectionView native scrolling and prefetching",
)
require(
    "guard virtualHistoryPosition != nil else { return }" in LIST
    and "installVirtualIndicatorIfNeeded" in LIST,
    "screens without a custom axis must return to the system indicator",
)
require(
    "UICollectionViewDiffableDataSource<Int, Item.ID>" in LIST
    and "NativeStaticUIKitCell" in LIST
    and "prefetchItemsAt indexPaths: [IndexPath]" in LIST,
    "chat rows must remain native reusable collection cells with prefetch callbacks",
)
require(
    "private let historyPageSize = 120" in CHAT
    and "private let historyPrefetchPages = 3" in CHAT
    and "olderPrefetch = Array(rows.dropLast(count))" in CHAT
    and "return Array(rows.suffix(count))" in CHAT,
    "prefetch may buffer three pages while consuming one native page per runway",
)

print("native-chat-scrollbar: passed")
