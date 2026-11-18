#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ME = (ROOT / "Sources" / "MeView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("Me page verification failed: " + message)


require(
    "let g = meGroup(for: it)" in ME,
    "the Me page must use the current functional grouping",
)
require(
    '"favorites", "moments", "works", "cards": return 2' in ME,
    "moments must be grouped into My Content",
)
require(
    'case "settings": return 4' in ME,
    "settings must have a separate current group",
)
require(
    '"favorites": 10' in ME
    and '"moments": 11' in ME
    and '"works": 12' in ME
    and '"cards": 13' in ME,
    "favorites must be first, moments second, then works and cards",
)
require('if item.action == "stickers" { continue }' in ME,
        "stickers must be hidden from the Me page")
require(
    "private var nativeMeList" in ME and "currentMeRows" in ME,
    "the Me page must render through the native list row builder",
)
require(
    ".listStyle(.insetGrouped)" in ME,
    "the Me page must use the native inset-grouped list style",
)
require(
    "private func meSectionTitle" in ME,
    "native list sections need user-facing headings",
)
require(
    "nativeMeItemRow(item)" in ME,
    "feature rows must stay in native list rows",
)
require(
    "nativeStat(value:" not in ME,
    "the old friends/active-days/moments stats strip must be removed",
)
for removed in (
    "orbitMeTop",
    "lightMeRows",
    "darkMeRows",
    "MeCardRowBackground",
):
    require(
        removed not in ME,
        f"the old Me page implementation must be deleted, not hidden: {removed}",
    )

print("me-current: passed")
