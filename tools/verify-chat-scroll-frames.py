#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DETAIL = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat scroll frame verification failed: " + message)


require(
    "onChange(of: contentFrame)" not in DETAIL,
    "message rows must not invalidate geometry observers on every scroll pixel",
)
require(
    DETAIL.count("onChange(of: frameCaptureTick)") >= 2,
    "long-press menu frames must refresh only after scrolling settles",
)
require(
    "frameBox.frames[message.id] = contentFrame" in DETAIL,
    "message frame capture must remain available for the long-press menu",
)

print("chat-scroll-frames: passed")
