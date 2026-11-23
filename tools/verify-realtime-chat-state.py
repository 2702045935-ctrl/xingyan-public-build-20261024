#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")
REALTIME = (ROOT / "Sources" / "Realtime.swift").read_text(encoding="utf-8")
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
MENTION_INDEX = (ROOT / "server" / "lib" / "mention-index.js").read_text(
    encoding="utf-8"
)
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("realtime chat state verification failed: " + message)


require(
    "Realtime.shared.setChatEventHandler { [weak self] event in" in APP
    and "if Self.isChatStateEvent(ev.type) {\n            chatEventHandler?(ev)"
    in REALTIME
    and "if Realtime.isChatStateEvent(ev.type) {\n                // AppState"
    in APP,
    "chat state events must bypass the lossy single-slot SwiftUI event path",
)
require(
    "case \"message\", \"chat\", \"read\", \"receipt\", \"sync\", \"recall\", \"ready\":"
    in REALTIME,
    "every event that mutates the conversation list must use the direct handler",
)
require(
    "var merged = mergeServerChat(incoming, local: current)" in APP
    and "let shouldAdvance: Bool" in APP
    and "guard shouldAdvance else { return }" in APP,
    "late realtime summaries must not roll a conversation row backwards",
)
require(
    "private func mergeSameMessageSummary(" in APP
    and "private func hasUnresolvedMention(server: Chat, local: Chat) -> Bool" in APP
    and "!hasUnresolvedMention(server: server, local: local)" in APP
    and "|| (row.unreadCount > 0 && before.lastMessage?.mentionMe == true)" in APP
    and "if (x.lastMessage?.mentionMe ?? false)"
    in APP,
    "same-message snapshots must preserve a pending mention until the server catches up",
)
require(
    "private func beginChatSnapshot() -> Int" in APP
    and "private func invalidateChatSnapshots()" in APP
    and "guard acceptsChatSnapshot(chatGeneration) else { return }" in APP
    and APP.count("invalidateChatSnapshots()") >= 7,
    "older conversation-list responses must not overwrite a newer live state",
)
require(
    "const index = (summaryContext && summaryContext.mentionIndex)" in SERVER
    and "mentionMe = hasUnreadMention(index, forUserId, readSeq);" in SERVER
    and "summaryContext.mentionIndex = mentionIndexForChat(chat.id, messageRows);"
    in SERVER
    and "messageRows.slice(-40)" not in SERVER,
    "unread mentions must survive beyond the most recent forty group messages",
)
require(
    "function hasUnreadMention(index, userId, lastReadSeq)" in MENTION_INDEX
    and "index.byUser.get(userId)" in MENTION_INDEX
    and "if (!message || message.recalled || seq <= 0) return null;" in MENTION_INDEX,
    "the server mention index must be incremental, per-user and recall-aware",
)
require(
    "python3 tools/verify-realtime-chat-state.py" in WORKFLOW
    and "node server/test/mention-index.test.js" in WORKFLOW,
    "realtime conversation-state regressions must run in the build gate",
)

print("realtime-chat-state: passed")
