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
    "chat top chrome must use the native glass material",
)
require(
    ".init(color: .clear, location: 1)" in CHAT_FLAT,
    "the native top material must fade without a visible strip",
)
require(
    "chatBackdrop" in CHAT and "ChatTopGlassBackdrop()" in CHAT,
    "the continuous chat wallpaper must stay beneath the native material",
)

print("group-top-frost: passed")
