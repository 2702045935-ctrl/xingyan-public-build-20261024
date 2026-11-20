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
    "static let gap: CGFloat = 4" in LAYOUT
    and "static let gridRadius: CGFloat = 9" in LAYOUT
    and "static let singleRadius: CGFloat = 12" in LAYOUT,
    "moments must use the compact thumbnail gap and corner scale",
)
require(
    "gridWidth = min(width, max(196, width * 0.60))" in LAYOUT
    and "gridWidth = min(width, max(228, min(252, width * 0.72)))" in LAYOUT
    and "singleWidth = min(width, max(184, width * 0.62))" in LAYOUT,
    "six/nine grids must stay compact while two-column and single media scale proportionally",
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
