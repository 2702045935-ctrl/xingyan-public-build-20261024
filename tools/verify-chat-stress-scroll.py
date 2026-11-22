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
    "if !isPrepending, !isPureAppend" in LIST
    and "(commonOrder != order || nextSignatures != signatures)" in LIST
    and "prependAnchor" in LIST,
    "history prepends must apply during touch motion with atomic anchor compensation",
)
require(
    "if isPrepending, !order.isEmpty" in LIST
    and "let recalcEnd" in LIST,
    "prepending must reuse unchanged row signatures and remeasure only the boundary",
)
require(
    "scroll.bounds.height * 2.75" in CHAT
    and "consumeOlderRunway(requireActiveMotion: true, offsetY: y)" in CHAT,
    "group history must use a viewport-relative prefetch runway",
)
require(
    'if chat.type == "group" { return true }' in CHAT
    and "if (chat.memberCount ?? 0) > 2 { return true }" in CHAT
    and "if (chat.memberIds ?? []).count >= 3 { return true }" in CHAT,
    "every group snapshot shape must enter the same history runway",
)
require(
    "func scrollViewWillBeginDragging" in LIST
    and "lastScrollState = false\n            publishScrollState(true)" in LIST,
    "a new physical gesture must re-arm the history runway even during deceleration",
)
require(
    "olderRunwayConsumedForGesture" in CHAT
    and "if isGroup { autoLoadOlder() }" not in CHAT
    and ".onAppear { autoLoadOlder() }" not in CHAT
    and "nearTopIds.contains(message.id) { autoLoadOlder() }" not in CHAT
    and "private let historyPageSize = 70" in CHAT
    and "let target = historyPageSize" in CHAT
    and "let canContinue = explicitMore ?? hasOlder" in CHAT
    and "guard canContinue, olderPrefetch.isEmpty, olderPrefetchTask == nil" in CHAT
    and "scheduleOlderPrefetch(before: nextCursor" in CHAT,
    "group history must only be consumed from the user's runway offset",
)
require(
    "loadedUsefulPage = more" in CHAT
    and "lastOlderLoad = .distantPast" in CHAT
    and "consumeOlderRunway(requireActiveMotion: true)" in CHAT,
    "every consumed history page must re-arm the runway during a long gesture",
)
require(
    "if merged.count > maxMessageWindow || more { hasOlder = true }" not in CHAT
    and "hasOlder = more" in CHAT,
    "reaching the actual first message must clear the phantom older page",
)
require(
    "else if !olderPrefetch.isEmpty" in CHAT
    and "consumeOlderRunway(requireActiveMotion: false)" in CHAT,
    "completed prefetches must auto-consume without another finger gesture",
)
require(
    "ChatScrollHandle.shared.prepareForPrepend()" in CHAT
    and "_ = ChatScrollHandle.shared.compensatePendingPrepend()" in LIST
    and "attributes.frame.minY - anchor.delta" in LIST,
    "history prepend must restore the B2611191645 anchor compensation path",
)
require(
    "private func consumeNewerRunway" in CHAT
    and "private func loadNewer() async" in CHAT
    and "API.shared.messagesSince(" in CHAT
    and "Array(merged.suffix(maxMessageWindow))" in CHAT,
    "scrolling back toward the present must refill newer messages bidirectionally",
)
require(
    all(f'kind = "{kind}"' in FIXTURE for kind in (
        "image", "pat", "system", "audio", "location", "video", "redpacket",
        "images", "file", "livephoto", "miniapp", "card", "gift", "transfer",
        "music", "announce", "mall"
    )),
    "the message stress fixture must cover the real chat message-kind distribution",
)
require(
    "flatMap(Int.init) ?? 8" in CONFIG,
    "the realistic single-group stress fixture must default to an 8-member family group",
)
require(
    'environment["XINGYAN_STRESS_GROUPS"].flatMap(Int.init) ?? 1' in CHAT
    or 'environment["XINGYAN_STRESS_GROUPS"].flatMap(Int.init) ?? 1' in CONFIG,
    "the default large-message stress run must be one exact single-group chat",
)
require(
    "let dominantCount = groupCount > 1 ? count * 3 / 4 : count" in FIXTURE,
    "a one-group stress run must materialize the complete requested history in that group",
)
require(
    'return "已加载 \\(messages.count) · \\(first)–\\(last) / \\(MessageStressFixture.count)"' in CHAT,
    "stress chat header must expose the visible sequence range against the total",
)

CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
require(
    "allowInsertionDuringScroll: true" in CHATS,
    "stress conversation lists must accept appended pages during active scrolling",
)
require(
    "let next: CGFloat = y > 8 ? 1 : 0" in CHATS
    and "lastReportedOffsetY" in (
        ROOT / "Sources" / "NativeChatList.swift"
    ).read_text(encoding="utf-8")
    and "abs(y - lastReportedOffsetY) >= 6" in (
        ROOT / "Sources" / "NativeChatList.swift"
    ).read_text(encoding="utf-8")
    and "panGestureRecognizer.delaysTouchesBegan = false" in (
        ROOT / "Sources" / "NativeChatList.swift"
    ).read_text(encoding="utf-8"),
    "conversation scrolling must not write exact offsets into SwiftUI every pixel",
)

NATIVE_CHAT_LIST = (ROOT / "Sources" / "NativeChatList.swift").read_text(encoding="utf-8")
NATIVE_CHAT_CELL = (ROOT / "Sources" / "NativeChatRowCell.swift").read_text(encoding="utf-8")
NATIVE_STATIC_LIST = (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8")
require(
    "allowInsertionDuringScroll,\n                   next.count > oldCount" in NATIVE_CHAT_LIST
    and "table.isDragging || table.isTracking || table.isDecelerating" in NATIVE_CHAT_LIST
    and "pendingItems = next" in NATIVE_CHAT_LIST,
    "only non-append changes may defer during touch motion",
)
require(
    "let prefetchLead = max(4_200, scrollView.bounds.height * 3.5)" in NATIVE_CHAT_LIST
    and "remaining < prefetchLead" in NATIVE_CHAT_LIST
    and "!endRequestInFlight" in NATIVE_CHAT_LIST,
    "the conversation list must prefetch one page three-and-a-half viewports before the tail",
)
require(
    "scrollViewWillBeginDragging" in NATIVE_CHAT_LIST
    and NATIVE_CHAT_LIST.count("endRequestInFlight = false") >= 3
    and "endRequestInFlight = false\n            startRequestInFlight = false" in NATIVE_CHAT_LIST
    and "结束拖动和减速必须释放预取锁" not in NATIVE_CHAT_LIST,
    "each new conversation gesture must release stale prefetch latches in both directions",
)
require(
    "self.prefetchEndRunwayIfNeeded(table)" in NATIVE_CHAT_LIST
    and NATIVE_CHAT_LIST.count("self.prefetchEndRunwayIfNeeded(table)") >= 2,
    "conversation appends must remeasure and refill the prefetch runway without another gesture",
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
    "conversation stress data must generate only the requested active window",
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
    "UIApplication.didBecomeActiveNotification" in NATIVE_CHAT_LIST
    and "visible.compactMap { dataSource.itemIdentifier(for: $0) }" in NATIVE_CHAT_LIST
    and "snapshot.reloadItems(ids)" in NATIVE_CHAT_LIST
    and "UIApplication.didBecomeActiveNotification" in NATIVE_STATIC_LIST
    and "collection.reloadItems(at: visible)" not in NATIVE_STATIC_LIST
    and "indexPath.item < snapshot.numberOfItems" in NATIVE_STATIC_LIST
    and "snapshot.reloadItems(ids)" in NATIVE_STATIC_LIST,
    "foreground recovery must repaint through the diffable snapshot without stale row paths",
)
require(
    "let existingChatIDs = Set(updated.list.lazy.map(\\.id))" in CHATS
    and "updated.list.append(contentsOf: freshChats)" in CHATS
    and "let existingEntryIDs = Set(stressChatEntries.lazy.map(\\.id))" in CHATS
    and ".filter { !existingEntryIDs.contains($0.id) }" in CHATS,
    "stress conversation snapshots must append only non-duplicate page IDs",
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
require(
    "if Set(nextIDs).count != nextIDs.count" in NATIVE_CHAT_LIST
    and "next = next.filter { seen.insert($0.id).inserted }" in NATIVE_CHAT_LIST,
    "the native list must coalesce duplicate IDs before creating its diffable snapshot",
)

MOMENTS = (ROOT / "Sources" / "MomentStressFixture.swift").read_text(encoding="utf-8")
require(
    '"#\\(index + 1) · \\(bodySamples[index % bodySamples.count])"' in MOMENTS,
    "Moments stress cards must expose their exact ordinal",
)
require(
    "private static let stressMomentWindow = 10_000" in (
        ROOT / "Sources" / "DiscoverView.swift"
    ).read_text(encoding="utf-8"),
    "the 10000-card Moments run must not trim leading rows while paging",
)
require(
    "private static let hardCap = 300_000" in CONFIG,
    "message stress must support a true 300k fixture",
)

print("chat-stress-scroll: passed")
