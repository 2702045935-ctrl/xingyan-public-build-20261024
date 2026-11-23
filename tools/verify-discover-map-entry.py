#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
DISCOVER = (ROOT / "Sources" / "DiscoverView.swift").read_text(encoding="utf-8")


def check(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("discover map verification failed: " + message)


check(
    "const DISCOVER_ACTIONS = ['moments', 'map'," in SERVER,
    "the server must allow the map action instead of normalizing it to soon",
)
check(
    'case "map": StarMapView()' in DISCOVER,
    "the map action must open the native StarMapView",
)
check(
    '"星轨地图": "map.fill"' in (
        ROOT / "Sources" / "RowIcon.swift"
    ).read_text(encoding="utf-8"),
    "the world entry must render with the native map icon",
)
check(
    'DiscoverItem(id: "d-map", label: "星轨地图"' in DISCOVER,
    "the world entry must render immediately as a builtin item",
)
check(
    "items = DiscoverItem.builtin" in DISCOVER,
    "the first world frame must render before the network catalog returns",
)
check(
    "private struct WorldTopIconPressStyle" not in DISCOVER
    and "systemTextFont(17, .semibold, relativeTo: .headline)" in DISCOVER
    and "buttonStyle(AppIconPressStyle())" in DISCOVER
    and "buttonStyle(MenuPressStyle())" in DISCOVER,
    "the world page must use native centered hierarchy and restrained press feedback",
)
check(
    "AppDesign.Control.sectionHeaderHeight" in DISCOVER
    and "AppDesign.Control.rowHeight" in DISCOVER
    and "AppDesign.Control.compactRowHeight" in DISCOVER
    and "Color.clear.frame(height: AppDesign.Spacing.xs)" in DISCOVER,
    "world sections and rows must use compact spacing with visible group separation",
)
check(
    "weak var discover: UIScrollView?" in (
        ROOT / "Sources" / "NavGlass.swift"
    ).read_text(encoding="utf-8")
    and "NativeTopScrollRegistry.shared.discover" in DISCOVER
    and "NativeScrollEdgeElementBridge(" in DISCOVER,
    "the world header must bind to the native scroll-edge material",
)

print("discover-map-entry: passed")
