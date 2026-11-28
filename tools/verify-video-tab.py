#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAIN = (ROOT / "Sources" / "MainTab.swift").read_text(encoding="utf-8")
BAR = (ROOT / "Sources" / "NativeTabBar.swift").read_text(encoding="utf-8")
VIDEO = (ROOT / "Sources" / "VideoTabView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("video tab verification failed: " + message)


require("VideoTabView()" in MAIN, "the video page must be mounted as a main tab")
require("(0..<5).contains(next)" in MAIN, "all five tab indexes must route")
require('UIImage(systemName: "play.rectangle")' in BAR,
        "the video tab must use the Apple play-rectangle icon")
require("items.count == 5" in BAR, "the tab bar must expose five items")
require("ChannelsView(embedded: true)" in VIDEO,
        "the video tab must mount the shared full-screen reel instead of a placeholder")
require(
    ".background(Color.black.opacity(0.16), in: Circle())" not in (
        ROOT / "Sources" / "FeedView.swift"
    ).read_text(encoding="utf-8"),
    "video chrome must use plain system controls without decorative black circles",
)

print("video-tab: passed")
