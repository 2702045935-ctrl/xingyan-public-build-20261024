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
NATIVE_CHAT_CELL = (ROOT / "Sources" / "NativeChatRowCell.swift").read_text(encoding="utf-8")
require(
    "allowInsertionDuringScroll,\n                   next.count > oldCount" in NATIVE_CHAT_LIST
    and "table.isDragging || table.isTracking || table.isDecelerating" in NATIVE_CHAT_LIST
    and "pendingItems = next" in NATIVE_CHAT_LIST,
    "only non-append changes may defer during touch motion",
)
require(
    "let prefetchLead = max(2_400, scrollView.bounds.height * 2.5)" in NATIVE_CHAT_LIST
    and "remaining < prefetchLead" in NATIVE_CHAT_LIST
    and "!endRequestInFlight" in NATIVE_CHAT_LIST,
    "the conversation list must prefetch one page two-and-a-half viewports before the tail",
)
require(
    "滚动期间不为未变化的 13k+ 行做全量相等比较" in NATIVE_CHAT_LIST
    and "appendPureTail(next, from: oldCount, keepPending: true)" in NATIVE_CHAT_LIST
    and "pendingItems = next" in NATIVE_CHAT_LIST,
    "active scrolling must avoid full-list equality work and reconcile after touch ends",
)
require(
    '!chatId.hasPrefix("stress-chat-")' in NATIVE_CHAT_CELL
    and "NativeGroupAvatarCache.shared.paths(chatId: chatId" in NATIVE_CHAT_CELL,
    "synthetic conversation rows must not start thousands of fake group-member API requests",
)
FIXTURE = (ROOT / "Sources" / "ChatStressFixture.swift").read_text(encoding="utf-8")
require(
    "static func chats(range: Range<Int>)" in FIXTURE
    and "return (lower..<upper).map(chat(at:))" in FIXTURE
    and "private static var cache" not in FIXTURE,
    "100k conversation stress data must generate only the requested active window",
)
require(
    "static let maxActiveWindow = 2_400" in FIXTURE
    and "range: stressWindowStart..<stressLoadedCount" in CHATS
    and "updated.list.removeFirst(min(removedCount, updated.list.count))" in CHATS
    and "stressChatEntries.removeFirst(min(removedCount, stressChatEntries.count))" in CHATS,
    "large conversation lists must keep a bounded active window while reading the full fixture",
)
require(
    "loadPreviousStressChatsIfNeeded()" in CHATS
    and "updated.list.insert(contentsOf: inserted, at: 0)" in CHATS
    and "stressChatEntries.removeLast(min(removedTail, stressChatEntries.count))" in CHATS,
    "scrolling back must refill the leading window and recycle the tail",
)
require(
    "let offsetAdjustment" in NATIVE_CHAT_LIST
    and "target.y += offsetAdjustment" in NATIVE_CHAT_LIST
    and "fromTop < max(1_600, scrollView.bounds.height * 1.5)" in NATIVE_CHAT_LIST,
    "both leading inserts and trailing removals must compensate their exact row height",
)
require(
    "updated.list.append(contentsOf: added)" in CHATS,
    "stress conversation snapshots must append new pages without rescanning all loaded rows",
)
require(
    ".onChange(of: app.chats) { _ in\n                guard !ChatStressFixture.isActive else { return }" in CHATS,
    "background chat refreshes must not rebuild the large stress fixture while it is on screen",
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
