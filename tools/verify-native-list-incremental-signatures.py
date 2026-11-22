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


require("let isPureAppend = !order.isEmpty" in LIST,
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
    "NativeStaticUIKitCell" in LIST
    and "nativeEligible" in LIST
    and "nativeRow" in LIST
    and "NativeChatTextRowView" in TEXT_ROWS
    and "NativeChatTimeRowView" in TEXT_ROWS,
    "text and complex message rows must use separate native cell paths",
)

print("native-list-incremental-signatures: passed")
