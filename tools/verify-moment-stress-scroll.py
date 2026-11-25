#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VIEW = (ROOT / "Sources" / "DiscoverView.swift").read_text(encoding="utf-8")
FIXTURE = (ROOT / "Sources" / "MomentStressFixture.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("moment stress scroll verification failed: " + message)


require(
    "pendingMomentPage" not in VIEW
    and "pendingStressLoadedCount" not in VIEW,
    "Moments pages must append while scrolling instead of stopping at the current page",
)
require(
    '"#\\(index + 1) · \\(bodySamples[index % bodySamples.count])"' in FIXTURE,
    "stress cards must expose exact ordinals for displacement checks",
)
require(
    '"已加载 \\(stressLoadedCount) / \\(MomentStressFixture.count)"' in VIEW,
    "stress header must expose the current loaded window",
)
require(
    "stressLoadedMoments.append(contentsOf:" in VIEW
    and "range: stressLoadedCount..<next" in VIEW
    and "stressLoadedMoments.removeFirst(min(removed, stressLoadedMoments.count))" in VIEW,
    "Moments stress data must consume one page and keep a bounded active window",
)
require(
    "momentPaging.moments = await Self.generateStressMoments(" in VIEW
    and "private static func generateStressMoments(range: Range<Int>) async -> [Moment]" in VIEW
    and "Task.detached(priority: .userInitiated)" in VIEW
    and "if let task = momentPaging.task {\n                await task.value" in VIEW
    and "scheduleMomentPrefetch()" in VIEW,
    "Moments stress pages must be generated off the main thread before display",
)
require(
    "@StateObject private var momentPaging = MomentPrefetchStore()" in VIEW
    and "@Published" not in VIEW.split("private final class MomentPrefetchStore", 1)[1].split("}", 1)[0],
    "prefetch output must stay outside SwiftUI observation until a visible page commits",
)

print("moment-stress-scroll: passed")
