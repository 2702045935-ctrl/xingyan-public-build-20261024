#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
NATIVE = (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat seamless prefetch verification failed: " + message)


require(
    "private var olderPrefetch: [Message]" in CHAT
    and "private func scheduleOlderPrefetch(" in CHAT
    and "private func takeOlderPrefetch()" in CHAT,
    "older history must stay prefetched ahead of the viewport",
)
require(
    "var olderNextCursor = 0" in CHAT
    and "let rawNext = page.messages.compactMap(\\.seq).min() ?? 0" in CHAT
    and "olderNextCursor = rawNext > 0 && rawNext < seq" in CHAT
    and "before: olderNextCursor > 0 ? olderNextCursor" in CHAT,
    "history paging must retain a forward-only server cursor across hidden pages",
)
require(
    "private final class ChatHistoryRuntime" in CHAT
    and "@State private var historyRuntime = ChatHistoryRuntime()" in CHAT
    and "nonmutating set { historyRuntime.lastOlderLoad = newValue }" in CHAT
    and "nonmutating set { historyRuntime.olderPrefetch = newValue }" in CHAT
    and "@State private var lastOlderLoad" not in CHAT
    and "@State private var olderPrefetch" not in CHAT,
    "prefetch bookkeeping must not invalidate the SwiftUI message list while scrolling",
)
require(
    "if olderPrefetch.isEmpty, let pending = olderPrefetchTask" in CHAT
    and "await pending.value" in CHAT,
    "foreground paging must reuse an in-flight prefetch instead of waiting twice",
)
require(
    "consumeOlderRunway(requireActiveMotion: true, offsetY: y)" in CHAT
    and "scroll.bounds.height * 3.5" in CHAT,
    "chat prefetch must use a viewport-relative runway",
)
require(
    "olderRunwayConsumedForGesture" not in CHAT
    and "newerRunwayConsumedForGesture" not in CHAT
    and "guard isGroup, initialScrollReady, hasOlder" not in CHAT
    and "if isGroup { autoLoadOlder() }" not in CHAT
    and "guard hasOlder, !loadingOlder, !loadingAllGroupHistory, !loading" not in CHAT
    and "guard !loadingOlder, !loadingAllGroupHistory" not in CHAT,
    "automatic history paging must be driven by the user scroll runway",
)
require(
    "ScrollGate.shared.setScrolling(false)" in CHAT
    and "consumeOlderRunwayOnHandoff()" in CHAT
    and "historyRuntime.pendingOlderHandoff = true" in CHAT,
    "deceleration handoff must consume only the page prepared for that gesture",
)
require(
    "private var oldestHistorySeq: Int" in CHAT
    and "historyRuntime.oldestLoadedSeq" in CHAT
    and "historyRuntime.oldestLoadedSeq = oldest" in CHAT
    and CHAT.count("oldestHistorySeq") >= 4
    and "let seq = messages.first?.seq" not in CHAT,
    "history cursors must skip leading system rows that have no sequence",
)
require(
    "private let historyPageSize = 120" in CHAT
    and "let target = historyPageSize" in CHAT
    and "let canContinue = explicitMore ?? hasOlder" in CHAT
    and "guard canContinue, olderPrefetch.isEmpty, olderPrefetchTask == nil" in CHAT
    and "olderPrefetch = visibleMessages(page.messages)" in CHAT
    and "before: seq" in CHAT
    and "let maxPages = 1" in CHAT,
    "chat prefetch must keep a bounded 120-message runway",
)
require(
    "scheduleOlderPrefetch(before: nextCursor" in CHAT
    and "knownIds: Set(bounded.map(\\.id))" in CHAT
    and "continues: more" in CHAT,
    "each consumed history page must enqueue exactly one fresh prefetch page",
)
require(
    "var loadedUsefulPage = false" in CHAT
    and "lastOlderLoad = .distantPast" in CHAT
    and "ChatScrollHandle.shared.markOlderRunwayIntent()" in CHAT
    and "ChatScrollHandle.shared.olderRunwayIntentActive" in CHAT
    and "olderRunwayBatchRemaining" not in CHAT
    and "consumeOlderRunway(requireActiveMotion: true)" in CHAT
    and "historyRuntime.pendingOlderHandoff" in CHAT,
    "continuous scrolling must fetch one page at a time and retain one handoff only",
)
require(
    "ChatScrollHandle.shared.endOlderRunwayIntent()" in CHAT
    and "private var olderRunwayGestureActive = false" in (
        ROOT / "Sources" / "ScrollProbe.swift"
    ).read_text(encoding="utf-8")
    and "olderRunwayIntentUntil" not in (
        ROOT / "Sources" / "ScrollProbe.swift"
    ).read_text(encoding="utf-8"),
    "history runway intent must follow the physical gesture instead of a timer",
)
require(
    "defer {\n            loadingNewer = false\n            if loadedUsefulPage" in CHAT
    and "defer {\n            loadingOlder = false\n            if loadedUsefulPage" in CHAT
    and "guard loadedUsefulPage else { return }" not in CHAT,
    "async history defers must not return from defer blocks",
)
require(
    "private func consumeOlderRunwayOnHandoff()" in CHAT
    and "!olderPrefetch.isEmpty" in CHAT
    and "consumeOlderRunwayOnHandoff()" in CHAT
    and "consumeNewerRunwayOnHandoff()" in CHAT
    and "var pendingOlderHandoff = false" in CHAT
    and "var pendingNewerHandoff = false" in CHAT
    and "historyRuntime.pendingOlderHandoff = true" in CHAT
    and "historyRuntime.pendingNewerHandoff = true" in CHAT
    and "A stopped\n                    // gesture must never start another network page by itself." in CHAT,
    "a stopped gesture may hand off only its already requested page and must not start another request",
)
require(
    "!ChatScrollHandle.shared.movingTowardOlder" in CHAT
    and "!ChatScrollHandle.shared.movingTowardNewer" in CHAT
    and "var movingTowardOlder: Bool" in (
        ROOT / "Sources" / "ScrollProbe.swift"
    ).read_text(encoding="utf-8")
    and "var movingTowardNewer: Bool" in (
        ROOT / "Sources" / "ScrollProbe.swift"
    ).read_text(encoding="utf-8")
    and "let naturalStep = max(96" in (
        ROOT / "Sources" / "ScrollProbe.swift"
    ).read_text(encoding="utf-8"),
    "history runway must follow the live scroll direction and ignore anchor-compensation jumps",
)
require(
    "} else if !olderPrefetch.isEmpty {" not in CHAT
    and "lastOlderLoad = .distantPast\n                    DispatchQueue.main.async {\n                        consumeOlderRunway(requireActiveMotion: false)" not in CHAT,
    "completed background prefetches must stay off-list until the next active scroll",
)
require(
    "private var newerPrefetch: [Message]" in CHAT
    and "private func scheduleNewerPrefetch(" in CHAT
    and "private func takeNewerPrefetch()" in CHAT
    and "newestKnownSeq" in CHAT
    and "messagesSince(" in CHAT,
    "newer history must prefetch and retain a cursor after older pages trim the window",
)
require(
    "consumeNewerRunway(requireActiveMotion: true)" in CHAT
    and "consumeNewerRunwayOnHandoff()" in CHAT
    and "historyRuntime.pendingNewerHandoff" in CHAT
    and "newerPrefetchTask" in CHAT
    and "scheduleNewerPrefetch(" in CHAT,
    "newer pages must continue during active travel with one prepared handoff",
)
require(
    "let refreshWindow = initial ? activeInitialMessageWindow : maxMessageWindow" in CHAT
    and "Array(visible.suffix(refreshWindow))" in CHAT,
    "realtime refreshes must preserve the user's loaded history window",
)
require(
    "private var shouldLoadCompleteGroupHistory: Bool" in CHAT
    and "!MessageStressFixture.isActive" in CHAT
    and "loadAllGroupHistory()" in CHAT
    and "if shouldLoadCompleteGroupHistory," in CHAT
    and 'UIConfig.num("chatEagerHistorySync", 0) > 0' in CHAT
    and "let pageSize = historyPageSize" in CHAT
    and "ChatScrollHandle.shared.prepareForPrepend()" in CHAT,
    "full-history sync must stay behind the diagnostic gate",
)
require(
    "let commitEveryPages = 6" in CHAT
    and "var staged: [String: Message] = [:]" in CHAT
    and "commitStaged()" in CHAT
    and "Task.sleep(nanoseconds: 35_000_000)" in CHAT
    and "while ChatScrollHandle.shared.moving, !Task.isCancelled" in CHAT
    and "Task.sleep(nanoseconds: 50_000_000)" in CHAT
    and 'loadingAllGroupHistory { return Tr("' not in CHAT
    and "let text = selectMode ? navTitleShown : navTitle" in CHAT,
    "background history sync must stay quiet and commit coalesced pages off the title",
)
require(
    "prependAnchor =" in NATIVE
    and "attributes.frame.minY - anchor.delta" in NATIVE
    and "clearPendingPrepend()" in NATIVE,
    "native prepend must restore the visible row before the next frame",
)
require(
    "private var deferredMeasureIDs" in NATIVE
    and "queueDeferredHeights(" in NATIVE
    and "drainDeferredHeightMeasurement()" in NATIVE
    and "queueDeferredHeights(\n                    idsToPrepare.filter { heights[$0] == nil }\n                )" in NATIVE,
    "fallback row heights must warm up incrementally after a moving-page insert",
)
require(
    "ChatScrollHandle.shared.prepareForPrepend()" in CHAT
    and "_ = ChatScrollHandle.shared.compensatePendingPrepend()" in NATIVE,
    "B2611191645 history prepends must use the original atomic compensation path",
)

print("chat-seamless-prefetch: passed")
