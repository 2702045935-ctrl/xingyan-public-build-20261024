#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
CHAT_FLAT = " ".join(CHAT.split())


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("group top frost verification failed: " + message)


require(
    "private struct ChatTopGlassBackdrop" in CHAT
    and "NativeGlassHeaderMaterial()" in CHAT,
    "chat top chrome must restore the native blur layer",
)
require(
    "sv.topEdgeEffect.style = .automatic" in (
        ROOT / "Sources" / "ScrollProbe.swift"
    ).read_text(encoding="utf-8"),
    "message scrolling must expose the system top-edge effect",
)
require(
    "private struct ChatHeaderGlassGroup" in CHAT
    and "Color.clear\n                            .glassEffect(.regular.interactive(), in: capsule)" in CHAT
    and "capsule.fill(tint)" not in CHAT.split("private var legacyGlass", 1)[0],
    "the previous circled chat header layout must use untinted native interactive glass",
)
require(
    "chatBackdrop" in CHAT and "ChatTopGlassBackdrop()" in CHAT,
    "the continuous chat wallpaper must stay beneath the native material",
)

print("group-top-frost: passed")
