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

print("discover-map-entry: passed")
