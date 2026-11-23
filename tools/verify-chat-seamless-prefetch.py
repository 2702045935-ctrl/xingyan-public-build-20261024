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
    "if olderPrefetch.isEmpty, let pending = olderPrefetchTask" in CHAT
    and "await pending.value" in CHAT,
    "foreground paging must reuse an in-flight prefetch instead of waiting twice",
)
require(
    "consumeOlderRunway(requireActiveMotion: true, offsetY: y)" in CHAT
    and "scroll.bounds.height * 2.75" in CHAT,
    "chat prefetch must use a viewport-relative runway",
)
require(
    "olderRunwayConsumedForGesture" not in CHAT
    and "newerRunwayConsumedForGesture" not in CHAT
    and "if isGroup { autoLoadOlder() }" not in CHAT
    and "guard hasOlder, !loadingOlder, !loadingAllGroupHistory, !loading" not in CHAT
    and "guard !loadingOlder, !loadingAllGroupHistory" not in CHAT,
    "automatic history paging must be driven by the user scroll runway",
)
require(
    "ScrollGate.shared.setScrolling(false)" in CHAT
    and "consumeOlderRunway(requireActiveMotion: false)" in CHAT,
    "history runway must also be consumed after deceleration ends",
)
require(
    "private var oldestHistorySeq: Int" in CHAT
    and "messages.lazy.compactMap(\\.seq).first(where: { $0 > 0 })" in CHAT
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
    and "consumeOlderRunway(requireActiveMotion: false)" in CHAT,
    "each completed page must immediately re-check the edge-distance runway",
)
require(
    "defer {\n            loadingNewer = false\n            if loadedUsefulPage" in CHAT
    and "defer {\n            loadingOlder = false\n            if loadedUsefulPage" in CHAT
    and "guard loadedUsefulPage else { return }" not in CHAT,
    "async history defers must not return from defer blocks",
)
require(
    "else if !olderPrefetch.isEmpty" in CHAT
    and "consumeOlderRunway(requireActiveMotion: false)" in CHAT,
    "a prefetched page must enter the runway after the finger has stopped",
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
    CHAT.count("consumeNewerRunway(requireActiveMotion: false)") >= 2
    and "newerPrefetchTask" in CHAT
    and "scheduleNewerPrefetch(" in CHAT,
    "completed newer prefetches must continuously return pages without extra finger gestures",
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
    and "let pageSize = historyPageSize" in CHAT
    and "ChatScrollHandle.shared.prepareForPrepend()" in CHAT,
    "ordinary conversations must backfill complete history without finger paging",
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
    "ChatScrollHandle.shared.prepareForPrepend()" in CHAT
    and "_ = ChatScrollHandle.shared.compensatePendingPrepend()" in NATIVE,
    "B2611191645 history prepends must use the original atomic compensation path",
)

print("chat-seamless-prefetch: passed")
