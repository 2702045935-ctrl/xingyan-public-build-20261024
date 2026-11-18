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
        and "recentChats: [Chat])?" in API,
        "badge polling must decode recent chat snapshots")
require("let merged = mergeServerChats(d.recentChats)" in APP
        and "if !AppState.sameChats(chats, merged)" in APP,
        "foreground badge polling must reconcile recent chat summaries")
require(".slice(0, 20)" in SERVER and ".map((chat) => chatSummary(chat, user.id))" in SERVER,
        "badge-counts must return a bounded recent chat snapshot")

print("chat-unread-reconcile: passed")
