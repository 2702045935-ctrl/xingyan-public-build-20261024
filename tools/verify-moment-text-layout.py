#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CARD = (ROOT / "Sources" / "NativeMomentRowCell.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("moment text layout verification failed: " + message)


require(
    "enum NativeMomentTextLayout" in CARD
    and "blankRun > 1" in CARD
    and "RichText.lines(normalized, size: 16.5)" in CARD,
    "moment text must normalise line endings, trailing spaces and excessive blank lines",
)
require(
    "momentUIFont(16.5, .regular, relativeTo: .body)" in CARD
    and "paragraph.lineSpacing = 7" in CARD
    and "bodyView.isScrollEnabled = false" in CARD,
    "moment copy must use the native editorial type scale and line rhythm",
)
require(
    "python3 tools/verify-moment-text-layout.py" in WORKFLOW,
    "moment text layout regression must run in the iOS gate",
)

print("moment-text-layout: passed")
