#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat-history-coverage verification failed: " + message)


require(
    "private var shouldLoadCompleteGroupHistory: Bool {\n        !MessageStressFixture.isActive\n    }"
    in CHAT
    and "if shouldLoadCompleteGroupHistory {" in CHAT
    and 'UIConfig.num("chatEagerHistorySync", 0) > 0' not in CHAT,
    "ordinary conversations must backfill complete history without a disabled-by-default flag",
)
require(
    "private func loadAllGroupHistory() async" in CHAT
    and "let maxPages = max(" in CHAT
    and "while hasOlder, pages < maxPages, !Task.isCancelled" in CHAT
    and "let page = try await API.shared.messages(" in CHAT
    and "before: before" in CHAT,
    "history backfill must page backwards until the server reports the actual start",
)
require(
    "const before = Number(query.get('before')) || Number.MAX_SAFE_INTEGER;" in SERVER
    and "m.seq < before" in SERVER
    and "hasMore: hasSince ? eligible.length > slice.length : slice.length === limit"
    in SERVER,
    "server history paging must remain sequence based without a date cutoff",
)
require(
    "commitEveryPages" in CHAT
    and "ChatScrollHandle.shared.prepareForPrepend()" in CHAT
    and "messages = Array((additions + messages).suffix(maxMessageWindow))" in CHAT,
    "history backfill must commit in bounded batches and preserve the visible anchor",
)
require(
    "python3 tools/verify-chat-history-coverage.py" in WORKFLOW,
    "complete history regression must run in the iOS gate",
)

print("chat-history-coverage: passed")
