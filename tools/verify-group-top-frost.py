#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
CHAT_FLAT = " ".join(CHAT.split())


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("group top frost verification failed: " + message)


require(
    "private struct NativeChatFrostedEdgeMaterial" in CHAT
    and ".systemUltraThinMaterialDark" in CHAT
    and "private struct ChatFrostedEdgeMask" in CHAT
    and "let base = C.pageBg" in CHAT
    and "ChatFrostedEdgeMask(edge: .top)" in CHAT,
    "chat top chrome must use the subtle native-frosted page-colour falloff",
)
require(
    "sv.topEdgeEffect.style = .automatic" in (
        ROOT / "Sources" / "ScrollProbe.swift"
    ).read_text(encoding="utf-8"),
    "message scrolling must expose the system top-edge effect",
)
require(
    "private struct ChatHeaderGlassGroup" in CHAT
    and "capsule.fill(lightInk" in CHAT
    and "capsule.stroke(C.hairline" in CHAT
    and ".glassEffect(" not in CHAT,
    "the circled chat header layout must use an opaque adaptive surface",
)
require(
    "chatBackdrop" in CHAT
    and "ChatFrostedEdgeMask(edge: .top)" in CHAT
    and "ChatTopGlassBackdrop" not in CHAT,
    "the top edge must no longer place a heavy glass layer over the wallpaper",
)

print("group-top-frost: passed")
