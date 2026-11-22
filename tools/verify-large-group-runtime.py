#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
GROUP = (ROOT / "Sources" / "GroupInfoView.swift").read_text(encoding="utf-8")
CONFIG = (ROOT / "Sources" / "StressTestConfiguration.swift").read_text(
    encoding="utf-8"
)
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
    and "function onlineMembersOfChat(chat, online)" in SERVER
    and "const recipients = onlineMembersOfChat(chat, online);" in SERVER
    and "for (const id of recipients)" in SERVER
    and "fanoutChatMessage(chat, message, user, clientId);" in SERVER,
    "message fanout must personalize summaries only for currently online members",
)
require(
    "summaryContext.unreadIndex = unreadIndexForMessages(messageRows);" in SERVER
    and "recentMentionRows: chat.type === 'group' ? messageRows.slice(-40) : null" in SERVER
    and "if (mentionAll) message.mentionAll = true;" in SERVER
    and "if mentionAll == true { return true }" in API,
    "large-group fanout must share unread and mention state without copying all members",
)
require(
    "relayToShardPorts(userId, payload, onlineShardPorts(userId));" in SERVER
    and "let userById = new Map();" in SERVER
    and "return userById.get(String(id || ''))" in SERVER
    and "if (!p.onMessage || !pushReady()) return;" in SERVER
    and "if (!Array.isArray(tokens[id]) || !tokens[id].length) return;" in SERVER
    and "Number(readIm().maxGroupMembers) || 100" in SERVER,
    "large-group routing must avoid offline shard fanout and linear user lookup",
)
require(
    "Number(query.get('limit') || 0)" in SERVER
    and "Number(query.get('cursor') || 0)" in SERVER
    and "hasMore: nextCursor < ordered.length" in SERVER,
    "the group member API must support bounded cursor pagination",
)
require(
    "Math.min(10000, Number(readIm().maxGroupMembers) || 100)" in SERVER,
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
require(
    "node server/test/large-group-10000.test.js" in WORKFLOW,
    "the 10000-member end-to-end runtime test must run in the iOS gate",
)
require(
    'profile == "group-300000-members-10000"' in CONFIG
    and "if largeGroupPressure { return 10_000 }" in CONFIG,
    "device stress must expose a one-variable 10000-member pressure profile",
)

print("large-group-runtime: passed")
