#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REALTIME = (ROOT / "Sources" / "Realtime.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("realtime chat direct verification failed: " + message)


chat_callback = REALTIME.index("if Self.isChatStateEvent(ev.type)")
coalesced_publish = REALTIME.index("if publishTask == nil", chat_callback)
require(
    "detailChatId" in REALTIME
    and "detailChatEventHandler" in REALTIME
    and "func setChatDetailEventHandler" in REALTIME
    and "func clearChatDetailEventHandler" in REALTIME
    and REALTIME.index("detailChatEventHandler?(ev)", chat_callback) < coalesced_publish,
    "realtime detail dispatch must be explicit",
)
require(
    "tick += 1\n            ev.tick = tick\n            chatEventHandler?(ev)"
    in REALTIME
    and "detailChatEventHandler?(ev)" in REALTIME
    and chat_callback < coalesced_publish,
    "active chats must receive message events before the coalesced public event",
)
require(
    "Realtime.shared.setChatDetailEventHandler(chatId: chat.id)" in CHAT
    and "Realtime.shared.clearChatDetailEventHandler(chatId: chat.id)" in CHAT
    and "private func handleRealtimeEvent(_ ev: PushEvent)" in CHAT
    and "guard ev.tick > lastRealtimeEventTick else { return }" in CHAT
    and "upsertVisibleMessage(message)" in CHAT,
    "the open chat must insert each message once without waiting for event coalescing",
)
require(
    "python3 tools/verify-realtime-chat-direct.py" in WORKFLOW,
    "realtime chat delivery regression must run in the iOS gate",
)

print("realtime-chat-direct: passed")
