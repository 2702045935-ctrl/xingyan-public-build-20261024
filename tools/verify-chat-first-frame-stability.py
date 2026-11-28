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
settle_start = CHAT.index("private func settleInitialNativeScroll()")
settle_end = CHAT.index("private func autoLoadOlder()", settle_start)
settle_block = CHAT[settle_start:settle_end]
require(
    "nativeMessageController.scrollToBottom" not in settle_block,
    "opening a chat must rely on the native pinned first frame instead of scrolling it again",
)
require(
    "initialOpenQuietUntil = Date().addingTimeInterval(0.55)" in CHAT
    and "private var shouldAnimateAutomaticBottomScroll" in CHAT
    and CHAT.count("animated: shouldAnimateAutomaticBottomScroll") == 2,
    "the first network reconciliation must pin without a visible bounce",
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
send_start = CHAT.index("private func send(kind: String")
send_end = CHAT.index("private func flushOutbox()", send_start)
send_block = CHAT[send_start:send_end]
require(
    CHAT.count("if Date() < followOwnSendUntil { return }") >= 2
    and "pinToBottomImmediately(force: true)" not in send_block
    and "pinToBottomSoon(force: true)" not in send_block,
    "own-message insertion must settle once without stacking repeated bottom pins",
)
require(
    "python3 tools/verify-chat-first-frame-stability.py" in WORKFLOW,
    "first-frame jump regression must run in the iOS gate",
)

print("chat-first-frame-stability: passed")
