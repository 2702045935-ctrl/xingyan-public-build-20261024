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
    'case "map": ComingSoonView(title: Tr("星轨地图"))' in DISCOVER
    and "StarWorldExperienceView()" not in DISCOVER
    and 'case "map": StarMapView()' not in DISCOVER,
    "the postponed 3D world must remain unreachable while the legacy map stays retired",
)
check(
    '"星轨地图": "map.fill"' in (
        ROOT / "Sources" / "RowIcon.swift"
    ).read_text(encoding="utf-8"),
    "the world entry must render with the native map icon",
)
check(
    "grouped.flatMap { $0 }.filter { $0.action != \"map\" }" in DISCOVER
    and 'DiscoverItem(id: "d-map", label: "星轨地图"' not in DISCOVER,
    "the postponed world entry must not render in Discover",
)
check(
    "items = DiscoverItem.builtin" in DISCOVER,
    "the first world frame must render before the network catalog returns",
)
check(
    "private struct WorldTopIconPressStyle" in DISCOVER
    and "systemTextFont(17, .semibold, relativeTo: .headline)" in DISCOVER
    and "buttonStyle(WorldTopIconPressStyle())" in DISCOVER
    and "buttonStyle(MenuPressStyle())" in DISCOVER,
    "the world page must use native centered hierarchy and restrained press feedback",
)
check(
    ".frame(height: 30)" in DISCOVER
    and ".frame(height: 72)" in DISCOVER
    and ".frame(height: 64)" in DISCOVER
    and "Color.clear.frame(height: 8)" in DISCOVER,
    "world sections and rows must use compact spacing with visible group separation",
)
check(
    "private enum WorldVisual" in DISCOVER
    and "static let social = [" in DISCOVER
    and "static let utility = [" in DISCOVER
    and "static let commerce = [" in DISCOVER
    and "static let local = [" in DISCOVER
    and "static let entertainment = [" in DISCOVER
    and '"music", "games", "channels", "look", "miniapps"' in DISCOVER
    and "static func keepsOriginalIcon(_ action: String?) -> Bool" in DISCOVER
    and "if keepsOriginalIcon {" in DISCOVER
    and "if let raw = color?.trimmingCharacters(in: .whitespacesAndNewlines)" in DISCOVER
    and "let custom = Color(hexString: raw, fallback: 0x4A90D9)" in DISCOVER
    and "for: item.color,\n            action: item.action" in DISCOVER
    and ".strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)" in DISCOVER
    and ".shadow(color: keepsOriginalIcon" in DISCOVER,
    "world entry icons must preserve branded artwork while normalizing generic tools",
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
