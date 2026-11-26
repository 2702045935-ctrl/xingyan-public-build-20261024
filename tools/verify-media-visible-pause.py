#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
MEDIA = (ROOT / "Sources" / "ChatMediaBubbles.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("media visibility pause verification failed: " + message)


require(
    ".onDisappear {\n                if voicePlayer.playingID == message.id {\n                    voicePlayer.stop()" in CHAT,
    "an audio message must stop when its row leaves the visible message window",
)
require(
    ".onDisappear {\n            if let o = timeObs, let p = player { p.removeTimeObserver(o) }" in MEDIA
    and "player?.pause()" in MEDIA,
    "the full-screen video player must pause when its page disappears",
)

print("media-visible-pause: passed")
