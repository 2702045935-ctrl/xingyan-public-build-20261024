#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LIST = (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8")
SCROLL = (ROOT / "Sources" / "ScrollProbe.swift").read_text(encoding="utf-8")
WINDOW = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat prepend anchor verification failed: " + message)


require(
    "attributes.frame.minY - collection.contentOffset.y" in LIST,
    "prepending must capture the visible row's exact viewport anchor",
)
require(
    "private func restoreVisibleAnchor(" in LIST
    and "attributes.frame.minY\n                - (previousOffset.y + anchor.delta)" in LIST
    and "target.y = min(max(target.y + layoutDelta, minimumY), maximumY)" in LIST,
    "prepending must translate the live native offset by the exact layout delta",
)
require(
    "ChatScrollHandle.shared.clearPendingPrepend()" in LIST,
    "exact native anchoring must clear the height-delta fallback",
)
require(
    "func clearPendingPrepend()" in SCROLL,
    "the scroll handle must support clearing a pending prepend",
)
require(
    "trimMessageWindowForOlderPage" not in WINDOW,
    "history insertion and tail-window trimming must not run as two snapshots",
)
require(
    "let bounded = merged.count > maxMessageWindow" in WINDOW,
    "the prepend and bounded message window must be committed atomically",
)
require(
    "collection.isDragging || collection.isTracking || collection.isDecelerating" in LIST
    and "if !isPrepending, !isPureAppend" in LIST
    and "(commonOrder != order || nextSignatures != signatures)" in LIST,
    "prepends must apply during touch motion through the native anchor compensation path",
)
require(
    "snapshot.insertItems(added, beforeItem: anchor)" in LIST
    and "snapshot.deleteItems(removed)" in LIST,
    "prepending must mutate only inserted, removed and changed identifiers",
)
require(
    "_ = ChatScrollHandle.shared.compensatePendingPrepend()" in LIST,
    "prepends without a visible anchor must use the original bounded fallback",
)
require(
    "ChatScrollHandle.shared.prepareForPrepend()" in WINDOW
    and "nativeHistoryApplyPending" not in WINDOW
    and "onApplyCompleted" not in LIST,
    "B2611191645 prepends must use the original immediate compensation path",
)

print("chat-prepend-anchor: passed")
