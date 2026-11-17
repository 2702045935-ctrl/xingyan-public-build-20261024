#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("group top frost verification failed: " + message)


require(
    "} else if isGroup {" in CHAT
    and "NativeGlassHeaderMaterial()" in CHAT,
    "group chats must use the native glass material in the top mask",
)
require(
    "NativeGlassHeaderMaterial()\n                                .opacity(0.78)" in CHAT,
    "the group top mask must remain subtly translucent",
)
require(
    "ChatImmersiveEdgeMask(path: backgroundPath" in CHAT,
    "the original chat wallpaper must stay beneath the material",
)

print("group-top-frost: passed")
