#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
GROUP = (ROOT / "Sources" / "GroupInfoView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("large-group runtime verification failed: " + message)


require(
    "chat.memberIds.slice(0, 64)" in SERVER
    and "memberIdsTruncated:" in SERVER
    and "summaryContext.memberPreviewIds" in SERVER,
    "large group summaries must carry only a bounded member preview",
)
require(
    "function fanoutChatMessage(chat, message, sender, clientId)" in SERVER
    and "if (!online.has(id)) continue;" in SERVER
    and "fanoutChatMessage(chat, message, user, clientId);" in SERVER,
    "message fanout must personalize summaries only for currently online members",
)
require(
    "Number(query.get('limit') || 0)" in SERVER
    and "Number(query.get('cursor') || 0)" in SERVER
    and "hasMore: nextCursor < ordered.length" in SERVER,
    "the group member API must support bounded cursor pagination",
)
require(
    "Math.min(10000, Number(im.maxGroupMembers) || 100)" in SERVER,
    "configured large groups must support a 10000-member ceiling",
)
require(
    "func chatMembersPage(chatId: String, limit: Int = 100, cursor: Int = 0)" in API
    and "cursor=\\(max(0, cursor))" in API,
    "the client API must request paginated group members",
)
require(
    "limit: 100,\n                cursor: 0" in GROUP
    and "private func loadMoreMembers() async" in GROUP
    and "cursor: nextCursor" in GROUP
    and "hasMore = page.hasMore" in GROUP,
    "group info must load bounded pages instead of requesting all members",
)
require(
    "python3 tools/verify-large-group-runtime.py" in WORKFLOW,
    "large-group runtime regression must run in the iOS gate",
)

print("large-group-runtime: passed")
