#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LAYOUT = (ROOT / "Sources" / "MomentMediaLayout.swift").read_text(encoding="utf-8")
FEED = (ROOT / "Sources" / "MomentFeedCard.swift").read_text(encoding="utf-8")
DISCOVER = (ROOT / "Sources" / "DiscoverView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("moment media grid verification failed: " + message)


require(
    "static func columns(for count: Int)" in LAYOUT
    and "case 2, 4:" in LAYOUT
    and "default:\n            return 3" in LAYOUT,
    "two/four images must use two columns and three-plus images must use three",
)
require(
    "static let gap: CGFloat = 5" in LAYOUT
    and "static let gridRadius: CGFloat = 2" in LAYOUT
    and "static let singleRadius: CGFloat = 12" in LAYOUT,
    "moments must use the compact thumbnail gap and corner scale",
)
require(
    "static let gridCellMax: CGFloat = 86" in LAYOUT
    and "let side = min(gridCellMax, usable / CGFloat(columns))" in LAYOUT
    and "singleWidth = min(width, max(184, width * 0.62))" in LAYOUT,
    "WeChat two/four/six/nine grids must share the measured 86pt square cell",
)
require(
    "MomentMediaLayout.singleImageSize(" in FEED
    and FEED.count("MomentMediaLayout.gridCellSize(") >= 1,
    "feed cards must share the canonical single-image and grid sizes",
)
require(
    "MomentMediaLayout.singleImageSize(" in DISCOVER
    and DISCOVER.count("MomentMediaLayout.gridCellSize(") >= 1,
    "moment detail grids must use the same media geometry as feed cards",
)
require(
    "python3 tools/verify-moment-media-grid.py" in WORKFLOW,
    "moment media geometry regression must run in the iOS gate",
)

print("moment-media-grid: passed")
