#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROFILE = (ROOT / "Sources" / "Profile.swift").read_text(encoding="utf-8")
DESIGN = (ROOT / "Sources" / "DesignSystem.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("people-flow design verification failed: " + message)


require(
    "struct AppFlowPanel<Content: View>: View" in DESIGN
    and "struct AppFlowDivider: View" in DESIGN
    and "struct AppEmptyState: View" in DESIGN
    and "struct AppFlowRow<Leading: View, Content: View, Trailing: View>: View" in DESIGN
    and PROFILE.count("AppFlowPanel {") >= 7
    and "PeopleFlow" not in PROFILE,
    "new-friends and face-group flows must share the same panel, divider and empty-state system",
)
require(
    "private var orbitHeader: some View" in PROFILE
    and "StarOrbitSearchField(" in PROFILE
    and "LazyVStack(spacing: 0)" in PROFILE
    and "AppFlowDivider(leading: 76)" in PROFILE
    and "AppCompactButton(title: Tr(\"接受\")" in PROFILE
    and "AppStatusPill(title: Tr(\"等待验证\"))" in PROFILE
    and "AppFlowRow" in PROFILE,
    "friend requests must use one grouped information flow with consistent row and action rhythm",
)
require(
    "struct AppPrimaryButton: View" in DESIGN
    and "struct AppIconTile: View" in DESIGN
    and "private var keypadDock: some View" in PROFILE
    and "private func codeSlot(_ index: Int) -> some View" in PROFILE
    and "AppFlowPanel {" in PROFILE
    and "OrbitTheme.jadeSoft" in PROFILE
    and "AppPrimaryButton(" in PROFILE
    and "private var hero: some View" not in PROFILE
    and "frame(width: 92, height: 92)" not in PROFILE,
    "face-group must use the shared surface system and a stable bottom keypad instead of the legacy hero",
)
require(
    "StarOrbitSearchField(" in PROFILE
    and "AppSectionHeader(title: Tr(\"搜索结果\")" in PROFILE
    and "AppIconTile(symbol: icon, size: 38)" in PROFILE
    and "addFriendSurface" not in PROFILE
    and "greenChip" not in PROFILE,
    "add-friend must reuse the same search, section, panel, row and action components",
)
require(
    "python3 tools/verify-people-flow-design.py" in WORKFLOW,
    "people-flow design regression must run in the iOS gate",
)

print("people-flow-design: passed")
