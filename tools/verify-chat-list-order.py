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

print("chat-list-order: passed")
