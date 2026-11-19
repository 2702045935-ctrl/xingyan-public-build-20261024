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
    and "MomentStressFixture.moments(\n                    range:" in VIEW,
    "Moments stress data must append only the new page instead of rebuilding all rows",
)

print("moment-stress-scroll: passed")
