#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PANELS = (ROOT / "Sources" / "Panels.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("plus panel verification failed: " + message)


require(
    "struct ChatPlusPanelMaterial" in PANELS
    and "Rectangle().fill(.regularMaterial)" in PANELS,
    "plus panel must use native system material",
)
require(
    "else if panel == .plus" in CHAT
    and "ChatPlusPanelMaterial()" in CHAT,
    "conversation plus panel must select the native material",
)
require(
    ".fill(LinearGradient(colors: tileColors(item.action)" not in PANELS,
    "plus tiles must not use decorative gradient cards",
)
require(
    "RoundedRectangle(cornerRadius: L.v(14, 4.5, 16)" not in PANELS,
    "plus tiles must not retain the old glass-card layers",
)

print("plus-panel-native: passed")
