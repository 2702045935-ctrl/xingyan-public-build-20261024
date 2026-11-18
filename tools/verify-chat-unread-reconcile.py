#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat unread reconcile verification failed: " + message)


require("var recentChats: [Chat]?" in API
        and "var unreadTotal: Int?" in API
        and "recentChats: [Chat])?" in API,
        "badge polling must decode recent chat snapshots")
require("let recent = mergeServerChats(d.recentChats)" in APP
        and "let recentIds = Set(d.recentChats.map(\\.id))" in APP
        and "combined.append(row)" in APP,
        "foreground badge polling must reconcile partial recent snapshots without dropping chats")
require(".slice(0, 20)" in SERVER and ".map((chat) => chatSummary(chat, user.id))" in SERVER,
        "badge-counts must return a bounded recent chat snapshot")
require(
    "unreadTotal: unreadTotalOf(user.id)" in SERVER
    and "if ((c.mutedFor || []).includes(userId)) return;" in SERVER
    and "authoritativeUnreadTotal = d.unreadTotal" in APP
    and "app.unreadForIcon" in (ROOT / "Sources" / "MainTab.swift").read_text(encoding="utf-8"),
    "foreground and APNs badges must share the same muted-aware total",
)
require(
    "now.timeIntervalSince(stamp) >= 2" in APP
    and "out.unread = server.unread" in APP
    and "optimisticChats[server.id] = nil" in APP,
    "a stable server snapshot must retire stale optimistic unread counters",
)
require(
    "type: 'read',\n      chatId: chat.id,\n      userId: user.id,\n      seq: lastSeq" in SERVER,
    "cross-device read events must identify the reading user",
)
require(
    "ev.userId.isEmpty || ev.userId == me?.id" in APP,
    "the client must accept old read events that omitted the user id",
)
require(
    "while !Task.isCancelled {\n                await self?.refreshDotCounts()" in APP,
    "dot polling must calibrate immediately before waiting for the next interval",
)

print("chat-unread-reconcile: passed")
