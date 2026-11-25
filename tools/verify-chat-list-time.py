#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORE = (ROOT / "Sources" / "Core.swift").read_text(encoding="utf-8")
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat list time verification failed: " + message)


require(
    "static func listConversation(_ s: String?) -> String" in CORE
    and "if seconds < 60 { return Tr(\"刚刚\") }" in CORE
    and "if seconds < 3_600" in CORE
    and 'Tr("分钟前")' in CORE
    and "return fClock.string(from: d)" in CORE,
    "conversation time must use just-now and minute labels before the clock",
)
require(
    CHATS.count("TimeFmt.listConversation(") >= 3
    and "TimeFmt.listApple(chat.listTimestamp)" not in CHATS,
    "all conversation-list time surfaces must use the same formatter",
)
require(
    "python3 tools/verify-chat-list-time.py" in WORKFLOW,
    "conversation-time regression must run in the iOS gate",
)

print("chat-list-time: passed")
