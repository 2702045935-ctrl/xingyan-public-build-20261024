#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LIST = (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat stress scroll verification failed: " + message)


require(
    "collection.isDragging || collection.isTracking || collection.isDecelerating" in LIST
    and "pending = next" in LIST,
    "history prepends must defer snapshot application until touch motion ends",
)
require(
    "if isPrepending, !order.isEmpty" in LIST
    and "let recalcEnd" in LIST,
    "prepending must reuse unchanged row signatures and remeasure only the boundary",
)
require(
    "if isGroup, y < 4200" in CHAT,
    "group history must prefetch with enough runway to avoid an empty top edge",
)
require(
    "if isGroup { autoLoadOlder() }" in CHAT
    and "let target = isGroup ? 160 : 200" in CHAT,
    "group prefetch must start at drag begin and load a larger history runway",
)

print("chat-stress-scroll: passed")
