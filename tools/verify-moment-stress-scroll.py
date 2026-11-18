#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VIEW = (ROOT / "Sources" / "DiscoverView.swift").read_text(encoding="utf-8")
FIXTURE = (ROOT / "Sources" / "MomentStressFixture.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("moment stress scroll verification failed: " + message)


require(
    "pendingMomentPage" in VIEW
    and "flushPendingMomentPage()" in VIEW
    and "if momentsScrollActive {" in VIEW,
    "Moments pages must be buffered while the feed is scrolling",
)
require(
    "pendingStressLoadedCount = max(pendingStressLoadedCount, next)" in VIEW,
    "stress pages must defer their LazyVStack window expansion",
)
require(
    '"#\\(index + 1) · \\(bodySamples[index % bodySamples.count])"' in FIXTURE,
    "stress cards must expose exact ordinals for displacement checks",
)
require(
    '"已加载 \\(stressLoadedCount) / \\(MomentStressFixture.count)"' in VIEW,
    "stress header must expose the current loaded window",
)

print("moment-stress-scroll: passed")
