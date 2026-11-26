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
    "!isPrepending && (commonOrder != order || nextSignatures != signatures)" in LIST
    and "prependAnchor" in LIST,
    "history prepends must apply during touch motion with atomic anchor compensation",
)
require(
    "if isPrepending, !order.isEmpty" in LIST
    and "let recalcEnd" in LIST,
    "prepending must reuse unchanged row signatures and remeasure only the boundary",
)
require(
    "if isGroup, y < 4200" in CHAT,
    "B2611191645 group history must use the fixed prefetch trigger",
)
require(
    "if isGroup { autoLoadOlder() }" in CHAT
    and "let target = isGroup ? 300 : 200" in CHAT
    and "let canContinue = explicitMore ?? hasOlder" in CHAT
    and "guard canContinue, olderPrefetch.isEmpty, olderPrefetchTask == nil" in CHAT
    and "scheduleOlderPrefetch(before: nextCursor" in CHAT,
    "group prefetch must keep the B2611191645 single-page history runway",
)
require(
    "ChatScrollHandle.shared.prepareForPrepend()" in CHAT
    and "_ = ChatScrollHandle.shared.compensatePendingPrepend()" in LIST
    and "attributes.frame.minY - anchor.delta" in LIST,
    "history prepend must restore the B2611191645 anchor compensation path",
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
    "allowInsertionDuringScroll: true" in CHATS,
    "stress conversation lists must accept appended pages during active scrolling",
)

NATIVE_CHAT_LIST = (ROOT / "Sources" / "NativeChatList.swift").read_text(encoding="utf-8")
require(
    "allowInsertionDuringScroll,\n"
    "                   next.count > oldCount,\n"
    "                   sameBoundaries,\n"
    "                   appendPureTail(next, from: oldCount, keepPending: true)"
    in NATIVE_CHAT_LIST
    and "table.isDragging || table.isTracking || table.isDecelerating" in NATIVE_CHAT_LIST
    and "pendingItems = next" in NATIVE_CHAT_LIST,
    "appended conversation pages must stay live during touch motion",
)
require(
    "allowInsertionDuringScroll,\n"
    "                   next.count == oldCount,\n"
    "                   slideWindowDuringScroll(next)"
    in NATIVE_CHAT_LIST
    and "private func slideWindowDuringScroll(_ next: [Item]) -> Bool" in NATIVE_CHAT_LIST,
    "equal-size conversation window slides must stay live during touch motion",
)
FIXTURE = (ROOT / "Sources" / "ChatStressFixture.swift").read_text(encoding="utf-8")
require(
    "private static var cache: [Chat]" in FIXTURE
    and "static func chats(range: Range<Int>)" in FIXTURE,
    "100k conversation stress data must materialize incrementally",
)
require(
    "let existingChatIDs = Set(updated.list.lazy.map(\\.id))" in CHATS
    and "let freshChats = added.filter { !existingChatIDs.contains($0.id) }" in CHATS
    and "updated.list.append(contentsOf: freshChats)" in CHATS,
    "stress conversation snapshots must append only fresh page identifiers",
)
require(
    "let isPureAppend = !order.isEmpty" in NATIVE_CHAT_LIST
    and "snapshot.appendItems(addedIDs, toSection: 0)" in NATIVE_CHAT_LIST,
    "pure conversation-list appends must update only the new identifiers",
)

MOMENTS = (ROOT / "Sources" / "MomentStressFixture.swift").read_text(encoding="utf-8")
require(
    '"#\\(index + 1) · \\(bodySamples[index % bodySamples.count])"' in MOMENTS,
    "100k Moments stress cards must expose their exact ordinal",
)

print("chat-stress-scroll: passed")
