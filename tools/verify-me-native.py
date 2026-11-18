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

print("me-native: passed")
