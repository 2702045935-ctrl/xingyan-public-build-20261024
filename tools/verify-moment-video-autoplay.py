#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CARD = (ROOT / "Sources" / "NativeMomentRowCell.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("moment video autoplay verification failed: " + message)


require(
    "AVPlayer(url: url)" in CARD
    and "player.isMuted = true" in CARD
    and "AVPlayerLayer(player: player)" in CARD,
    "moment videos must use a muted native AVPlayerLayer rather than a static image",
)
require(
    "setPlaybackActive(true)" in (
        ROOT / "Sources" / "NativeMomentFeed.swift"
    ).read_text(encoding="utf-8")
    and "didEndDisplaying cell" in (
        ROOT / "Sources" / "NativeMomentFeed.swift"
    ).read_text(encoding="utf-8")
    and "playImmediately(atRate: 1)" in CARD
    and "player?.pause()" in CARD
    and "setPlaybackActive(false)" in CARD,
    "autoplay must follow native cell visibility and pause when leaving",
)
require(
    "actions.openVideo(url)" in CARD,
    "tapping an inline video must still open the full-screen player",
)
require(
    "python3 tools/verify-moment-video-autoplay.py" in WORKFLOW,
    "moment video autoplay regression must run in the iOS gate",
)

print("moment-video-autoplay: passed")
