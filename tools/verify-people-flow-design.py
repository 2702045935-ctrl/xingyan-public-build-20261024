#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROFILE = (ROOT / "Sources" / "Profile.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("people-flow design verification failed: " + message)


require(
    "private struct PeopleFlowPanel<Content: View>: View" in PROFILE
    and "private struct PeopleFlowDivider: View" in PROFILE
    and "private struct PeopleFlowEmptyState: View" in PROFILE
    and PROFILE.count("PeopleFlowPanel {") >= 6
    and "OrbitTheme.cardBackground()" in PROFILE
    and "clipShape(OrbitTheme.card)" in PROFILE,
    "new-friends and face-group flows must share the same panel, divider and empty-state system",
)
require(
    "private var orbitHeader: some View" in PROFILE
    and "StarOrbitSearchField(" in PROFILE
    and "LazyVStack(spacing: 0)" in PROFILE
    and "PeopleFlowDivider(leading: 76)" in PROFILE
    and ".frame(height: 76)" in PROFILE
    and ".frame(height: 72)" in PROFILE
    and "Capsule().fill(OrbitTheme.jadeDeep)" in PROFILE,
    "friend requests must use one grouped information flow with consistent row and action rhythm",
)
require(
    "private var keypadDock: some View" in PROFILE
    and "private func codeSlot(_ index: Int) -> some View" in PROFILE
    and "PeopleFlowPanel {" in PROFILE
    and "OrbitTheme.jadeSoft" in PROFILE
    and "OrbitTheme.fieldRaised" in PROFILE
    and "private var hero: some View" not in PROFILE
    and "frame(width: 92, height: 92)" not in PROFILE,
    "face-group must use the shared surface system and a stable bottom keypad instead of the legacy hero",
)
require(
    "python3 tools/verify-people-flow-design.py" in WORKFLOW,
    "people-flow design regression must run in the iOS gate",
)

print("people-flow-design: passed")
