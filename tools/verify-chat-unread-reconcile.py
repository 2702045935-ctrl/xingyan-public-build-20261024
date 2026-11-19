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
        and "unreadTotal: Int?, recentChats: [Chat])?" in API,
        "badge polling must decode recent chat snapshots")
require("let recent = mergeServerChats(d.recentChats)" in APP
        and "let recentIds = Set(d.recentChats.map(\\.id))" in APP
        and "combined.append(row)" in APP,
        "foreground badge polling must reconcile partial recent snapshots without dropping chats")
require(
    "let serverRows = Dictionary(uniqueKeysWithValues: d.recentChats.map { ($0.id, $0) })" in APP
    and "out.unread = server.unread" in APP
    and "out.flagged = server.flagged" in APP
    and "optimisticChats[row.id] = nil" in APP,
    "foreground polling must let an authoritative same-message snapshot clear stale row unread",
)
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
    "private func adjustAuthoritativeUnread(from old: Chat?, to new: Chat?)" in APP
    and "let delta = unreadContribution(new) - unreadContribution(old)" in APP
    and APP.count("authoritativeUnreadTotal = nil") == 1,
    "realtime chat changes must preserve the server total and apply only their own delta",
)
require(
    "for c in chats where c.muted != true { n += c.unreadCount }" in APP,
    "the fallback badge total must keep the same muted-session rule as the server",
)
require(
    "type: 'read',\n      chatId: chat.id,\n      userId: user.id,\n      seq: lastSeq" in SERVER,
    "cross-device read events must identify the reading user",
)
require(
    "function scheduleBadgePush" in SERVER
    and "silent: true" in SERVER
    and "'content-available': 1" in SERVER
    and "silent ? 'background' : 'alert'" in SERVER,
    "offline devices need a badge-only APNs update after cross-device read",
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
