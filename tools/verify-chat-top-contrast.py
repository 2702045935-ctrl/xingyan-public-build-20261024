#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DETAIL = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat top contrast verification failed: " + message)


require(
    "adaptiveTopGlyphShadow" in DETAIL
    and "? OfficialAccountVisual.glow : adaptiveTopGlyphShadow" in DETAIL,
    "top-bar glyphs need an adaptive contrast edge",
)
require(
    "private struct NativeChatFrostedEdgeMaterial" in DETAIL
    and ".systemUltraThinMaterialDark" in DETAIL
    and ".systemUltraThinMaterialLight" in DETAIL
    and "private struct ChatFrostedEdgeMask" in DETAIL
    and "let base = C.pageBg" in DETAIL
    and "ChatFrostedEdgeMask(edge: .top)" in DETAIL
    and "ChatFrostedEdgeMask(edge: .bottom)" in DETAIL
    and "ChatTopGlassBackdrop" not in DETAIL
    and "ChatImmersiveEdgeMask" not in DETAIL,
    "chat chrome must use the subtle native-frosted top and bottom masks",
)
require(
    "base.opacity(0.66)" in DETAIL
    and "base.opacity(0.32)" in DETAIL
    and "ChatMaterialGrainOverlay" not in DETAIL,
    "chat masks must keep the page-colour falloff without heavy glass or grain",
)
require(
    "titleOutline: adaptiveTopOutline.opacity(0.55)" in DETAIL,
    "selection-mode title must retain a readable outline",
)

print("chat-top-contrast: passed")
