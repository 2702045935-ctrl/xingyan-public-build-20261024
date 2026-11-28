#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LAYOUT = (ROOT / "Sources" / "MomentMediaLayout.swift").read_text(encoding="utf-8")
FEED = (ROOT / "Sources" / "NativeMomentRowCell.swift").read_text(encoding="utf-8")
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
    "MomentMediaLayout.singleImageSize(" in FEED
    and FEED.count("MomentMediaLayout.gridCellSize(") >= 1,
    "feed cards must share the canonical single-image and grid sizes",
)
require(
    "static let gap: CGFloat = 5" in LAYOUT
    and "static let gridRadius: CGFloat = 5" in LAYOUT
    and "static let singleRadius: CGFloat = 5" in LAYOUT
    and "gridWidth = min(width, 177)" in LAYOUT
    and "gridWidth = min(width, 269)" in LAYOUT,
    "the 2/3-column grid must match WeChat's 86pt cells and 5pt gaps",
)
require(
    "singleMaxWidth: CGFloat = 220" in LAYOUT
    and "singleMaxHeight: CGFloat = 300" in LAYOUT
    and "maxWidth / knownSize.width" in LAYOUT
    and "singleImageSize(knownSize: knownSize" in FEED,
    "single photos must preserve small source dimensions and only cap oversized media",
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
