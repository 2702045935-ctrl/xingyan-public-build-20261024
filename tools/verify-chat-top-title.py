#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat top title verification failed: " + message)


require(
    "Text(chatTopTitle)\n                    .font(pf(17, .semibold))" in CHATS,
    "the chat top title must use the WhatsApp-style 17pt semibold navigation title",
)
require(
    "Text(chatTopTitle)\n                    .font(pf(22, .bold))" not in CHATS,
    "the oversized chat top title must not return",
)
require(
    ".background(Capsule().fill(Color(.systemRed)))" in CHATS
    and ".overlay(Capsule().stroke(ChatListVisual.badgeRing, lineWidth: 1.5))" in CHATS
    and "nativeUnreadTotalBadge" in CHATS,
    "the title unread count must use the native chat-list badge treatment",
)

print("chat-top-title: passed")
