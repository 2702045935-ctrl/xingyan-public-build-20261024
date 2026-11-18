#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFERRED = (ROOT / "Sources" / "ChatDeferred.swift").read_text(encoding="utf-8")
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")
DETAIL = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat entry verification failed: " + message)


require(
    "ChatDetailView(" in DEFERRED
    and "initialMessages: app.prefetched[chat.id] ?? []" in DEFERRED,
    "the destination must render the real chat page with an immediate local snapshot",
)
require(
    "@State private var ready" not in DEFERRED
    and "await Task.yield()" not in DEFERRED,
    "there must be no deferred blank-page gate before the chat page",
)
require(
    "DeferredChatView(chat: chat)" in CHATS,
    "chat navigation must keep a single destination wrapper",
)
require(
    "prepareChatForImmediatePresentation(chat)" in CHATS
    and "prepareChatForImmediatePresentation(_ chat: Chat)" in APP,
    "the tapped row must hydrate its local snapshot before navigation",
)
require(
    "withSoftChatTransition" not in CHATS,
    "chat navigation must not delay behind an artificial transition gate",
)
require(
    "init(chat: Chat, initialMessages: [Message] = [])" in DETAIL
    and "_messages = State(initialValue: seed)" in DETAIL,
    "the chat page must seed its first rendered message window",
)

print("chat-entry: passed")
