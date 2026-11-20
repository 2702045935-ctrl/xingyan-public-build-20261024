#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CARD = (ROOT / "Sources" / "MomentFeedCard.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("moment text layout verification failed: " + message)


require(
    "enum MomentTextLayout" in CARD
    and "blankRun <= 1" in CARD
    and "RichText.lines(normalized(raw), size: size)" in CARD,
    "moment text must normalise line endings, trailing spaces and excessive blank lines",
)
require(
    "MomentTextLayout.attributed(text, size: 15.5)" in CARD
    and ".tracking(0.08)" in CARD
    and ".lineSpacing(5.15)" in CARD
    and ".fixedSize(horizontal: false, vertical: true)" in CARD,
    "moment copy must use WeChat-like type scale, tracking and line rhythm",
)
require(
    "python3 tools/verify-moment-text-layout.py" in WORKFLOW,
    "moment text layout regression must run in the iOS gate",
)

print("moment-text-layout: passed")
