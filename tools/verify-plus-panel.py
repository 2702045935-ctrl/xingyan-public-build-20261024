#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PANELS = (ROOT / "Sources" / "Panels.swift").read_text(encoding="utf-8")
NATIVE = (ROOT / "Sources" / "NativePlusPanel.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("plus panel verification failed: " + message)


require(
    "struct ChatPlusPanelMaterial" in PANELS
    and "Rectangle().fill(C.floatingSurface)" in PANELS
    and ".regularMaterial" not in PANELS,
    "the panel background must use the opaque floating surface",
)
require(
    "struct NativePlusPanel: UIViewRepresentable" in NATIVE
    and "final class NativePlusPanelView: UIView, UIScrollViewDelegate" in NATIVE
    and "private final class NativePlusTileView: UIControl" in NATIVE,
    "plus panel implementation must exist as a native paged view",
)
require(
    "box.backgroundColor = NativePlusTileView.color(for: item.action)" in NATIVE,
    "plus tiles must use the simplified solid icon surface",
)
require(
    ".shadow(" not in NATIVE
    and "RoundedRectangle(cornerRadius: L.v(14, 4.5, 16)" not in NATIVE,
    "plus tiles must not restore decorative cards or shadows",
)
require(
    "pointSize: L.v(20.5, 6.2, 23)" in NATIVE,
    "plus tile symbols must use the refined visual weight",
)

print("plus-panel: passed")
