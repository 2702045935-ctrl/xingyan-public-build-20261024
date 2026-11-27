#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VIEW = (ROOT / "Sources" / "DiscoverView.swift").read_text(encoding="utf-8")
FEED = (ROOT / "Sources" / "NativeMomentFeed.swift").read_text(encoding="utf-8")
FIXTURE = (ROOT / "Sources" / "MomentStressFixture.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("moment stress scroll verification failed: " + message)


moments = VIEW.split("struct MomentsView: View", 1)[1].split(
    "struct MomentGroup:", 1
)[0]
feed_body = moments.split("var body: some View", 1)[1].split(
    ".navigationBarBackButtonHidden", 1
)[0]

require(
    "NativeMomentFeed(" in moments,
    "Moments must use the native feed kernel",
)
require(
    "ScrollView {" not in feed_body
    and "LazyVStack" not in feed_body
    and "momentList" not in moments,
    "Moments must not retain the SwiftUI list or a fallback rendering path",
)
require(
    "onApproachingEnd:" in moments
    and "await loadMoreMoments()" in moments,
    "native prefetch must own page consumption",
)
require(
    '"已加载 \\(stressLoadedCount) / \\(MomentStressFixture.count)"' in moments,
    "stress rows must expose the currently loaded count",
)
require(
    "setStressLoadedMoments(" in moments
    and "stressLoadedMoments.append(contentsOf:" not in moments,
    "stress pages must use the same revisioned data path as server pages",
)
require(
    "UITableView" in FEED
    and "UITableViewDiffableDataSource" in FEED
    and "UITableViewDataSourcePrefetching" in FEED
    and "prefetchRowsAt indexPaths" in FEED
    and "UIHostingConfiguration" in FEED,
    "feed reuse, diffing and page prefetch must be native",
)
require(
    "onAppear" not in FEED
    and "ScrollView {" not in FEED
    and "endRequestInFlight" in FEED
    and "requestNextPage()" in FEED,
    "feed paging must be a single native runway without SwiftUI on-appear triggers",
)
require(
    '"#\\(index + 1) · \\(bodySamples[index % bodySamples.count])"' in FIXTURE,
    "stress cards must expose exact ordinals for displacement checks",
)

print("moment-stress-scroll: passed")
