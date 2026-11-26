#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat top title verification failed: " + message)


require(
    "Text(navTitle)\n                    .font(pf(17, .semibold))" in CHATS,
    "the chat top title must use the compact 17pt semibold navigation title",
)
require(
    "Text(chatTopTitle)\n                    .font(pf(22, .bold))" not in CHATS,
    "the oversized chat top title must not return",
)
require(
    'return unreadTotal > 0 ? "\\(chatListBrandTitle)(\\(unreadTotal))" : chatListBrandTitle'
    in CHATS
    and "chatsHeaderH: CGFloat { 44 }" in CHATS
    and "chatsSearchH: CGFloat { 36 }" in CHATS,
    "the title unread count must stay inline with compact header spacing",
)
require(
    "private var chatHeaderMenu: some View" in CHATS
    and "ForEach(ChatFilter.allCases)" in CHATS
    and "chooseFilter(item)" in CHATS,
    "the title must expose every conversation category and change the active filter",
)
require(
    "showSearch = true" in CHATS
    and "scrollChatsToTop()" in CHATS
    and "NativeChatListScrollRegistry.shared.chats" in CHATS,
    "the title menu must open search and scroll the native conversation list to the top",
)
require(
    "private var chatHeaderIsSyncing: Bool" in CHATS
    and "manualChatSync" in CHATS
    and "await app.syncRecentMessages(chatCount: 20, limit: 50)" in CHATS
    and "await app.syncDeviceChats()" in CHATS,
    "the title must reflect sync state and reuse the existing conversation sync pipeline",
)

print("chat-top-title: passed")
