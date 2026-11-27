#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PANELS = (ROOT / "Sources" / "Panels.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
NATIVE_PLUS = (ROOT / "Sources" / "NativePlusPanel.swift").read_text(encoding="utf-8")


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
    "struct NativePlusPanel: UIViewRepresentable" in NATIVE_PLUS
    and "final class NativePlusPanelView: UIView, UIScrollViewDelegate" in NATIVE_PLUS
    and "stride(from: 0, to: max(1, items.count), by: 8)" in NATIVE_PLUS
    and "let usable = max(1, bounds.width - gridPad * 2 - gridGap * 3)" in NATIVE_PLUS
    and "NativePlusPanel(items: plusItems" in CHAT
    and "struct PlusPanel: View" not in PANELS,
    "plus panel must have one native paged implementation with the existing grid metrics",
)
require(
    "RoundedRectangle(cornerRadius: L.v(14, 4.5, 16)" not in PANELS,
    "plus tiles must not retain the old glass-card layers",
)
require(
    "_plusItems = State(initialValue: Self.localPlusItems)" in CHAT
    and "private static var localPlusItems: [PlusItem]" in CHAT
    and "private func refreshPlusPanelConfig() async" in CHAT
    and '.task(id: "plus-panel-\\(chat.id)")' in CHAT
    and "if panel == .plus && plusItems.isEmpty" not in CHAT
    and "NativePlusPanel(items: plusItems" in CHAT
    and ".accessibilityHidden(panel != .plus)" in CHAT,
    "the plus panel must be prebuilt from local defaults and refreshed in the background",
)

print("plus-panel-native: passed")
