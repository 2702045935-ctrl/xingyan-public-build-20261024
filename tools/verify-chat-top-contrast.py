#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DETAIL = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat top contrast verification failed: " + message)


require(
    "adaptiveTopGlyphShadow" in DETAIL
    and ".shadow(color: adaptiveTopGlyphShadow" in DETAIL,
    "top-bar glyphs need an adaptive contrast edge",
)
require(
    "private struct ChatTopGlassBackdrop" in DETAIL
    and "NativeScrollEdgeElementBridge(" in DETAIL
    and "ChatScrollHandle.shared.scroll" in DETAIL
    and "scheme == .light" in DETAIL
    and "ChatImmersiveEdgeMask(path: backgroundPath,\n                                              edge: .top" in DETAIL
    and "topBarContrastScrim" not in DETAIL,
    "light chat chrome must preserve the November extended wallpaper mask and dark chrome must use the system edge",
)
require(
    "titleOutline: adaptiveTopOutline.opacity(0.55)" in DETAIL,
    "selection-mode title must retain a readable outline",
)

print("chat-top-contrast: passed")
