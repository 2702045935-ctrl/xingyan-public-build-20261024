#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DISCOVER = (ROOT / "Sources" / "DiscoverView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("cover immediate-refresh verification failed: " + message)


require(
    "@State private var coverPreview: UIImage?" in DISCOVER
    and "coverPreview = image" in DISCOVER
    and DISCOVER.index("coverPreview = image")
    < DISCOVER.index("stageLocalImagePreview(image, prefix: \"local-cover\")"),
    "the cropped cover must render locally before async work starts",
)
require(
    "if let coverPreview {\n"
    "                Image(uiImage: coverPreview)\n"
    "                    .resizable()\n"
    "                    .scaledToFill()" in DISCOVER,
    "the visible cover must prefer the local preview",
)
require(
    "python3 tools/verify-cover-immediate.py" in WORKFLOW,
    "cover immediate-refresh regression must run in the iOS gate",
)

print("cover-immediate: passed")
