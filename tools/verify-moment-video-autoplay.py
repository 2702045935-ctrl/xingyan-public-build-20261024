#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CARD = (ROOT / "Sources" / "MomentFeedCard.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("moment video autoplay verification failed: " + message)


require(
    "struct MomentAutoplayVideo: View" in CARD
    and "AVPlayer(url: url)" in CARD
    and "next.isMuted = true" in CARD,
    "moment videos must use a muted inline AVPlayer rather than a static image",
)
require(
    "visible >= 0.60" in CARD
    and "safeCenter" in CARD
    and "visible >= 0.86" in CARD
    and "playImmediately(atRate: 1)" in CARD
    and "player?.pause()" in CARD
    and ".onDisappear" in CARD,
    "autoplay must start only near the viewport and pause when leaving",
)
require(
    "onOpenVideo(videoURL)" in CARD,
    "tapping an inline video must still open the full-screen player",
)
require(
    "python3 tools/verify-moment-video-autoplay.py" in WORKFLOW,
    "moment video autoplay regression must run in the iOS gate",
)

print("moment-video-autoplay: passed")
