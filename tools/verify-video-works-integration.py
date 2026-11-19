#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FEED = (ROOT / "Sources" / "FeedView.swift").read_text(encoding="utf-8")
VIDEO = (ROOT / "Sources" / "VideoTabView.swift").read_text(encoding="utf-8")
PAGES = (ROOT / "Sources" / "MiscPages.swift").read_text(encoding="utf-8")
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("video/works integration verification failed: " + message)


require(
    "var embedded = false" in FEED
    and "var startingItems: [FeedItem]? = nil" in FEED
    and "var startingItemID: String? = nil" in FEED,
    "shared reel must support tab embedding and a starting Works item",
)
require(
    "ChannelsView(embedded: true)" in VIDEO
    and ".hidesTabBar(!embedded)" in FEED
    and ".swipeBack(!embedded)" in FEED,
    "the video tab must share the reel while preserving the main tab bar",
)
require(
    ".fullScreenCover(item: $playing)" in PAGES
    and "ChannelsView(startingItems: visibleWorks" in PAGES
    and "startingItemID: w.id" in PAGES,
    "Works tiles must open the same reel at the selected work",
)
require(
    "if let startingItems, !startingItems.isEmpty" in FEED
    and "items = startingItems" in FEED,
    "the shared reel must seed deterministically from Works instead of another network scan",
)
require(
    "var visibility: String?" in FEED
    and "let visibility = (item.visibility ?? \"\").lowercased()" in PAGES
    and "let allKnown = (mine + mineFromAll + all)" in PAGES
    and "likedWorks = allKnown" in PAGES,
    "Works, likes and private tabs must share one visibility-aware item universe",
)
require(
    "function feedVisibleTo(item, viewerId)" in SERVER
    and "visibility: it.visibility || 'public'" in SERVER
    and "visibility: ['private', 'partial', 'exclude']" in SERVER,
    "feed visibility must be persisted, returned and enforced by the server",
)
require(
    "python3 tools/verify-video-works-integration.py" in WORKFLOW,
    "video/Works integration regression must run in the iOS gate",
)

print("video-works-integration: passed")
