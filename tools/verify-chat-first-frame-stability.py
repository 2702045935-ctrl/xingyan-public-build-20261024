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
    and CHAT.count("if initialOpenSettling {") >= 2,
    "first-frame settling must suppress direct and native size-change pinning",
)
require(
    "private func settleInitialNativeScroll()" in CHAT
    and "nativeMessageController.scrollToBottom(animated: false)" in CHAT,
    "the shared native chat must settle before its first visible frame",
)
require(
    "collection.alpha = initiallyPinnedToBottom ? 0 : 1" in (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8")
    and "completeInitialBottom" in (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8"),
    "native chats must reveal only after the first bottom position is committed",
)
require(
    CHAT.count("initialOpenSettling = false") >= 2,
    "settling must end after restore, user interaction, or transition completion",
)
require(
    "python3 tools/verify-chat-first-frame-stability.py" in WORKFLOW,
    "first-frame jump regression must run in the iOS gate",
)

print("chat-first-frame-stability: passed")
