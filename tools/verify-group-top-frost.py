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
    and "NativeScrollEdgeElementBridge(" in CHAT
    and "ChatScrollHandle.shared.scroll" in CHAT,
    "chat top chrome must use the system scroll-edge effect",
)
require(
    "sv.topEdgeEffect.style = .automatic" in (
        ROOT / "Sources" / "ScrollProbe.swift"
    ).read_text(encoding="utf-8"),
    "message scrolling must expose the system top-edge effect",
)
require(
    "ChatHeaderGlassGroup" not in CHAT
    and CHAT.count("NativeGlassCircleBackground()") >= 4
    and ".glassEffect(.regular.interactive(), in: shape)" in (
        ROOT / "Sources" / "NavGlass.swift"
    ).read_text(encoding="utf-8"),
    "the top-bar controls need individual native interactive glass circles",
)
require(
    "chatBackdrop" in CHAT and "ChatTopGlassBackdrop()" in CHAT,
    "the continuous chat wallpaper must stay beneath the native material",
)

print("group-top-frost: passed")
