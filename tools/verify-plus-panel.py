#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PANELS = (ROOT / "Sources" / "Panels.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("plus panel verification failed: " + message)


start = PANELS.find("struct PlusPanel")
end = PANELS.find("\nprivate struct PlusTileStyle", start)
require(start >= 0 and end > start, "plus panel implementation must exist")
panel = PANELS[start:end]
require(
    "struct ChatPlusPanelMaterial" in PANELS
    and "Rectangle().fill(.regularMaterial)" in PANELS,
    "the panel background must use native system material",
)
require(
    ".fill(tileColors(item.action).first ?? C.green)" in panel,
    "plus tiles must use the simplified solid icon surface",
)
require(
    ".shadow(" not in panel
    and "RoundedRectangle(cornerRadius: L.v(14, 4.5, 16)" not in panel,
    "plus tiles must not restore decorative cards or shadows",
)
require(
    "size: L.v(20.5, 6.2, 23)" in panel,
    "plus tile symbols must use the refined visual weight",
)

print("plus-panel: passed")
