#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
GROUP = (ROOT / "Sources" / "GroupInfoView.swift").read_text(encoding="utf-8")
TEST = (ROOT / "server" / "test" / "chat-actions.test.js").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("group membership send verification failed: " + message)


require("if (chat.dismissed || (chat.type === 'group' && !(chat.memberIds || []).length))" in SERVER
        and "return { error: '群聊已解散' }" in SERVER,
        "the message API must reject dismissed groups before writing a message")
require("refreshChatAccessStateFromDisk(true)" in SERVER,
        "message sends must refresh chat membership from durable state")
require("chrisChatUnavailable" in CHAT
        and "guard !chatUnavailable" in CHAT
        and 'reason.contains("群聊已解散")' in CHAT,
        "the chat page must stop pending sends after removal or dismissal")
require("LocalPersistence.saveOutbox(chat.id, [])" in GROUP,
        "leaving or dismissing must clear the group pending outbox")
require("退群后不应还能发送" in TEST and "解散后不应还能发送" in TEST,
        "server regressions must cover sending after leave and dismissal")

print("group-membership-send: passed")
