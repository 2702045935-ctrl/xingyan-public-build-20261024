#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat-list-order verification failed: " + message)


require("var listTimestamp" in API, "chat must expose a fallback timestamp")
require("var listActivityDate" in API, "chat must expose the ordering date")
require("$0.listActivityDate" in APP and "$1.listActivityDate" in APP,
        "chat ordering must use the shared fallback date")
require(CHATS.count("TimeFmt.listApple(chat.listTimestamp)") >= 2,
        "all chat-list time labels must use the shared fallback timestamp")
require("TimeFmt.date($0.lastMessage?.createdAt ?? $0.updatedAt)" not in APP,
        "ordering must not discard a valid updatedAt after a malformed message time")
ENTRIES = CHATS.split("private func nativeChatEntries", 1)[1].split(
    "private var nativeChatAppearance", 1
)[0]
require(
    ENTRIES.find('id: "weather"') < ENTRIES.find("if snapshot.list.isEmpty")
    and ENTRIES.count('id: "weather"') == 1,
    "weather must remain in the top utility rows instead of trailing the conversations",
)
require(
    "private var sortedOfficialRowKeys: [String]" in CHATS
    and "for key in sortedOfficialRowKeys" in ENTRIES
    and "systemOfficialRows" in CHATS
    and "return left > right" in CHATS,
    "platform official entries must follow WeChat-style recent-activity ordering",
)
require(
    "locallyHiddenLastMessage" in APP
    and "locallyHiddenLastMessageAt" in APP
    and "hiddenChatHasNewerActivity(incoming)" in APP,
    "stale realtime snapshots must not revive a deleted or hidden conversation",
)
require(
    "timeIntervalSince(locallyHiddenAt[id] ?? .distantPast) > 3" not in APP,
    "deleted or hidden conversations must not expire back into the list after three seconds",
)

print("chat-list-order: passed")
