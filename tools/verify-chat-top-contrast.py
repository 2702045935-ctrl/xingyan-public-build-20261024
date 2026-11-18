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
    and "NativeGlassHeaderMaterial()" in DETAIL
    and "scheme == .light" in DETAIL
    and "ChatImmersiveEdgeMask(path: backgroundPath" in DETAIL
    and "edge: .top" in DETAIL
    and "topBarContrastScrim" not in DETAIL,
    "chat chrome must keep the wallpaper extension and native top material",
)
require(
    "} else if scheme == .light {\n"
    "                        ChatImmersiveEdgeMask(path: backgroundPath" in DETAIL
    and "themeVersion: chatTheme.version)\n"
        "                            ChatTopGlassBackdrop()" not in DETAIL,
    "light chat chrome must keep the wallpaper extension without the dark blur layer",
)
require(
    "titleOutline: adaptiveTopOutline.opacity(0.55)" in DETAIL,
    "selection-mode title must retain a readable outline",
)

print("chat-top-contrast: passed")
