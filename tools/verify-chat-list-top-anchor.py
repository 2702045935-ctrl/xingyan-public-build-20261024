#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
NATIVE = (ROOT / "Sources" / "NativeChatList.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat list top-anchor verification failed: " + message)


require(
    "let keepsTopAnchor = previousOffset.y <= minimumYBeforeApply + 2" in NATIVE
    and "target.y += offsetAdjustment" in NATIVE
    and "if keepsTopAnchor { target.y = minimumY }" in NATIVE
    and "target.y = keepsTopAnchor ? minimumY : previousOffset.y" in NATIVE,
    "diffable updates and pure appends must preserve a top anchor when already at top",
)
require(
    NATIVE.count("table.setContentOffset(previousOffset, animated: false)") >= 2,
    "foreground and metric reloads must restore their previous viewport",
)
require(
    '.id("\\(app.me?.id ?? "")-\\(chatFilter)")' in CHATS,
    "chat lists must reset scroll identity when the active account changes",
)
require(
    "let snapshot = hasInitializedChatCache ? cachedSnapshot : chatSnapshot()" in CHATS
    and "let entries = hasInitializedChatCache" in CHATS
    and "nativeChatEntries(snapshot)" in CHATS
    and "items: entries" in CHATS,
    "the search anchor and rows must exist in the first rendered list frame",
)
require(
    "python3 tools/verify-chat-list-top-anchor.py" in WORKFLOW,
    "chat-list auto-bottom regression must run in the iOS gate",
)

print("chat-list-top-anchor: passed")
