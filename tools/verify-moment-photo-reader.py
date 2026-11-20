#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
READER = (ROOT / "Sources" / "MomentPhotoReader.swift").read_text(encoding="utf-8")
DISCOVER = (ROOT / "Sources" / "DiscoverView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("moment photo reader verification failed: " + message)


require(
    "struct MomentPhotoReader: View" in READER
    and "PhotoPager(" in READER
    and "readerPanel" in READER
    and "onIndexChange" in READER,
    "moments images must open a dedicated photo reading surface",
)
require(
    "moment.author?.name" in READER
    and "TimeFmt.ago(moment.createdAt)" in READER
    and "RichText.linkified(text)" in READER,
    "photo reading surface must retain author, complete time and original copy",
)
require(
    "onOpenComments" in READER
    and "onOpenLikes(likes)" in READER
    and "showingLiked" in READER,
    "photo reading surface must keep comments, likes and like state interactive",
)
require(
    "MomentPhotoReader(" in DISCOVER
    and "viewerMoment = moment" in DISCOVER
    and "private func closeMomentReader()" in DISCOVER,
    "moment image taps must route into the reading surface and close cleanly",
)
require(
    "python3 tools/verify-moment-photo-reader.py" in WORKFLOW,
    "moment photo reader regression must run in the iOS gate",
)

print("moment-photo-reader: passed")
