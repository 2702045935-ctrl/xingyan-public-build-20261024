#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LIST = (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8")
TEXT_ROWS = (ROOT / "Sources" / "NativeChatTextRowCell.swift").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("native list incremental signature verification failed: " + message)


require("var isPureAppend = !order.isEmpty" in LIST
        and "order[order.count - 1 - commonTail]" in LIST
        and "if !isPrepending, !isPureAppend" in LIST,
        "tail appends must avoid full prepend scans")
require(
    "nextSignatures = Dictionary(uniqueKeysWithValues: next.map {" not in LIST,
    "scrolling updates must not regenerate every row signature",
)
require(
    "old == item" in LIST and "let existing = signatures[item.id]" in LIST,
    "only new or changed rows may rebuild their signature",
)
require(
    "if nextOrder == order && nextSignatures == signatures" in LIST,
    "unchanged scroll frames must return before diff bookkeeping",
)
require(
    "if isPureAppend {" in LIST
    and "snapshot.insertItems(added, beforeItem: anchor)" in LIST
    and "if wasAtBottom" in LIST
    and "drainDeferredWarmup()" in LIST,
    "append updates must stay incremental and defer warmup until scrolling ends",
)
require(
    "NativeStaticUIKitCell" in LIST
    and "nativeEligible" in LIST
    and "nativeRow" in LIST
    and "NativeChatTextRowView" in TEXT_ROWS
    and "NativeChatMediaRowView" in (
        ROOT / "Sources" / "NativeChatMediaRowCell.swift"
    ).read_text(encoding="utf-8")
    and "NativeChatTimeRowView" in TEXT_ROWS,
    "text and high-frequency media rows must use native cell paths",
)
require(
    "lastReportedOffsetY" in LIST
    and ">= 24" in LIST
    and "panGestureRecognizer.delaysTouchesBegan = false" in LIST
    and "long.cancelsTouchesInView = false" in TEXT_ROWS,
    "scroll tracking must stay direct and avoid per-pixel SwiftUI callbacks",
)

print("native-list-incremental-signatures: passed")
