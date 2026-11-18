#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LIST = (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
FIXTURE = (ROOT / "Sources" / "MessageStressFixture.swift").read_text(encoding="utf-8")
CONFIG = (ROOT / "Sources" / "StressTestConfiguration.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat stress scroll verification failed: " + message)


require(
    "collection.isDragging || collection.isTracking || collection.isDecelerating" in LIST
    and "pending = next" in LIST,
    "history prepends must defer snapshot application until touch motion ends",
)
require(
    "if isPrepending, !order.isEmpty" in LIST
    and "let recalcEnd" in LIST,
    "prepending must reuse unchanged row signatures and remeasure only the boundary",
)
require(
    "if isGroup, y < 4200" in CHAT,
    "group history must prefetch with enough runway to avoid an empty top edge",
)
require(
    "if isGroup { autoLoadOlder() }" in CHAT
    and "let target = isGroup ? 160 : 200" in CHAT,
    "group prefetch must start at drag begin and load a larger history runway",
)
require(
    all(f'kind = "{kind}"' in FIXTURE for kind in (
        "image", "pat", "system", "audio", "location", "video", "redpacket",
        "images", "file", "livephoto", "miniapp", "card", "gift", "transfer",
        "music", "announce", "mall"
    )),
    "100k stress fixture must cover the real chat message-kind distribution",
)
require(
    "flatMap(Int.init) ?? 8" in CONFIG,
    "the realistic single-group stress fixture must default to an 8-member family group",
)
require(
    'environment["XINGYAN_STRESS_GROUPS"].flatMap(Int.init) ?? 1' in CHAT
    or 'environment["XINGYAN_STRESS_GROUPS"].flatMap(Int.init) ?? 1' in CONFIG,
    "the default 100k stress run must be one exact single-group chat",
)
require(
    "let dominantCount = groupCount > 1 ? count * 3 / 4 : count" in FIXTURE,
    "a one-group stress run must materialize all 100000 messages in that group",
)
require(
    'return "已加载 \\(messages.count) · \\(first)–\\(last) / \\(MessageStressFixture.count)"' in CHAT,
    "stress chat header must expose the visible sequence range against the 100k total",
)

CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
require(
    "allowInsertionDuringScroll: false" in CHATS,
    "stress conversation lists must defer row insertion until scrolling ends",
)

print("chat-stress-scroll: passed")
