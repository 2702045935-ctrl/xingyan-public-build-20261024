#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat first-frame stability failed: " + message)


require(
    "private var initialOpenSettling" in CHAT
    and CHAT.count("if initialOpenSettling { return }") >= 2,
    "first-frame settling must suppress direct and native size-change pinning",
)
require(
    "ChatInitialBottomAnchor(enabled: !initialScrollReady)" in CHAT
    and "defaultScrollAnchor(enabled ? UnitPoint.bottom : nil)" in CHAT
    and "if #available(iOS 17.0, *)" in CHAT
    and "for delay in [0, 24, 70, 150, 260]" not in CHAT,
    "chat entry must use one native bottom anchor instead of repeated visible pinning",
)
require(
    "nativeMessageController.scrollToBottom(animated: false)" in CHAT,
    "native chats must retain their single committed initial bottom placement",
)
require(
    "private var usesNativeMessageList: Bool" in CHAT
    and "} else {\n            nativeMessageList" in CHAT
    and "initiallyPinnedToBottom: true" in CHAT,
    "long chats must use the premeasured native list to avoid first-scroll stalls",
)
require(
    "collection.alpha = initiallyPinnedToBottom ? 0 : 1" in (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8")
    and "completeInitialBottom" in (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8"),
    "native chats must reveal only after the first bottom position is committed",
)
require(
    CHAT.count("initialOpenSettling = false") >= 3,
    "settling must end after restore, user interaction, or transition completion",
)
require(
    "python3 tools/verify-chat-first-frame-stability.py" in WORKFLOW,
    "first-frame jump regression must run in the iOS gate",
)

print("chat-first-frame-stability: passed")
