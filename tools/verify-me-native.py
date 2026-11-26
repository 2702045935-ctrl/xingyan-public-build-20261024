#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ME = (ROOT / "Sources" / "MeView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("native me page verification failed: " + message)


require(
    "List {" in ME and ".listStyle(.insetGrouped)" in ME,
    "me page must use the native grouped list",
)
for forbidden in [
    ".scrollContentBackground(.hidden)",
    ".listRowBackground(C.meCardBg)",
    ".toolbarBackground(.regularMaterial, for: .navigationBar)",
    ".toolbarBackground(scheme == .dark ? .hidden : .visible",
    "private var mePageCanvasColor",
]:
    require(forbidden not in ME, "custom appearance override remains: " + forbidden)
require(
    ".navigationBarTitleDisplayMode(.large)" in ME
    and "Section {" in ME
    and ".font(.headline)" in ME,
    "native navigation, section and typography hierarchy are required",
)
require(
    "items = DiscoverItem.builtinMe" in ME,
    "the native me rows must render before the network catalog returns",
)
require(
    "private func meSectionHeader" in ME
    and ".textCase(nil)" in ME
    and ".frame(width: 29, height: 29)" in ME
    and "LinearGradient(" in ME
    and "private enum MeVisual" in ME
    and "static func colors(for action: String?) -> [Color]" in ME
    and "colors: MeVisual.colors(for: item.action)" in ME
    and "colors: MeVisual.violet" in ME
    and "Color(hexString: item.color" not in ME
    and ".stroke(Color.white.opacity(0.18), lineWidth: 0.5)" in ME,
    "me section labels and row symbols must use the refined native hierarchy",
)

print("me-native: passed")
