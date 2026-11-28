#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
PROFILE = (ROOT / "Sources" / "Profile.swift").read_text(encoding="utf-8")
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("friend/block semantics verification failed: " + message)


require(
    "var addState: String?" in API
    and "var addReason: String?" in API
    and "var blockedMe: Bool?" in API,
    "search results must decode the server's authoritative add/block state",
)
require(
    'let state = sentTo.contains(u.id) ? "requested" : (u.addState ?? rel)' in PROFILE
    and 'state == "blocked"' in PROFILE
    and 'state == "blocked_by_peer" || state == "banned"' in PROFILE
    and 'disabledResultChip(Tr("已加入黑名单"))' in PROFILE
    and 'disabledResultChip(Tr("暂时无法添加"))' in PROFILE,
    "blocked and unavailable accounts must not show an add-friend action",
)
require(
    ".contentShape(Rectangle())\n        .onTapGesture {\n            target = u\n        }" in PROFILE,
    "tapping a search result must open the profile before sending a request",
)

blocked = SERVER.index("else if (blocked) { addState = 'blocked'")
friend = SERVER.index("else if (relation === 'friend')")
pending = SERVER.index("else if (relation === 'requested')")
require(
    blocked < friend < pending,
    "block state must take precedence over stale friendship request state",
)

print("friend-block-semantics: passed")
