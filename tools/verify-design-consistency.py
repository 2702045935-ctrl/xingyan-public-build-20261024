#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "Sources"
DESIGN = (SOURCES / "DesignSystem.swift").read_text(encoding="utf-8")
ORBIT = (SOURCES / "OrbitTheme.swift").read_text(encoding="utf-8")
PROFILE = (SOURCES / "Profile.swift").read_text(encoding="utf-8")
CONTACTS = (SOURCES / "ContactsView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("design consistency verification failed: " + message)


require(
    "enum AppDesign" in DESIGN
    and "enum Spacing" in DESIGN
    and "enum Radius" in DESIGN
    and "enum Control" in DESIGN
    and "enum Type" in DESIGN
    and "enum Motion" in DESIGN
    and "struct AppFlowPanel" in DESIGN
    and "struct AppFlowRow" in DESIGN
    and "struct AppPrimaryButton" in DESIGN
    and "struct AppCompactButton" in DESIGN
    and "struct AppStatusPill" in DESIGN
    and "struct AppEmptyState" in DESIGN
    and "struct AppIconTile" in DESIGN,
    "the shared design system must define tokens and production components",
)
require(
    "AppDesign.Radius.panel" in ORBIT
    and "AppDesign.Radius.control" in ORBIT
    and "AppDesign.Control.searchHeight" in (
        SOURCES / "StarOrbitViews.swift"
    ).read_text(encoding="utf-8")
    and "AppDesign.Motion.press" in (
        SOURCES / "MainTab.swift"
    ).read_text(encoding="utf-8"),
    "legacy theme, search and press primitives must delegate to the shared system",
)

violations = []
for path in SOURCES.glob("*.swift"):
    if path.name == "DesignSystem.swift":
        continue
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    for index, line in enumerate(lines, start=1):
        stripped = line.strip()
        if "cornerRadius:" not in stripped:
            continue
        after = stripped.split("cornerRadius:", 1)[1].lstrip()
        if after[:1].isdigit():
            violations.append(f"{path.name}:{index}")
require(
    not violations,
    "numeric corner radii must be replaced by AppDesign.Radius tokens: "
    + ", ".join(violations[:12]),
)

require(
    "struct ContactAvatarPressStyle" not in CONTACTS
    and "struct ContactTopIconPressStyle" not in CONTACTS
    and "struct ContactSearchPressStyle" not in CONTACTS
    and "struct GroupMemberChipPressStyle" not in PROFILE
    and "AppPressStyle()" in CONTACTS
    and "AppPressStyle()" in PROFILE,
    "migrated pages must use the shared press feedback",
)
require(
    "AppFlowPanel {" in PROFILE
    and "AppFlowRow" in PROFILE
    and "AppCompactButton" in PROFILE
    and "AppPrimaryButton" in PROFILE
    and "AppStatusPill" in PROFILE
    and "AppFlowPanel {" in CONTACTS
    and "AppFlowRow" in CONTACTS
    and "AppFlowDivider" in CONTACTS,
    "the people-flow pages must reuse shared panels, rows, actions and statuses",
)
require(
    "python3 tools/verify-design-consistency.py" in WORKFLOW,
    "design consistency regression must run in the iOS gate",
)

print("design-consistency: passed")
