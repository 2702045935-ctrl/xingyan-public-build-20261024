#!/usr/bin/env python3
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "Sources"
DESIGN = (SOURCES / "DesignSystem.swift").read_text(encoding="utf-8")
ORBIT = (SOURCES / "OrbitTheme.swift").read_text(encoding="utf-8")
MAIN = (SOURCES / "MainTab.swift").read_text(encoding="utf-8")
PROFILE = (SOURCES / "Profile.swift").read_text(encoding="utf-8")
CONTACTS = (SOURCES / "ContactsView.swift").read_text(encoding="utf-8")
CHATS = (SOURCES / "ChatsView.swift").read_text(encoding="utf-8")
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
    and "struct MenuPressStyle: ButtonStyle" in DESIGN
    and "AppDesign.Motion.press" in DESIGN,
    "legacy theme, search and press primitives must delegate to the shared system",
)
require(
    "struct GroupCard<Content: View>: View" in MAIN
    and "cornerRadius: AppDesign.Radius.panel" in MAIN
    and "var horizontalInset: CGFloat = AppDesign.Spacing.md" in MAIN
    and ".padding(.horizontal, horizontalInset)" in MAIN
    and "struct MenuRow: View" in MAIN
    and "AppDesign.Type.listTitle" in MAIN
    and "AppDesign.Control.menuRowHeight" in MAIN
    and "struct HairLine" in (
        SOURCES / "Core.swift"
    ).read_text(encoding="utf-8")
    and "AppDesign.Control.hairline" in (
        SOURCES / "Core.swift"
    ).read_text(encoding="utf-8"),
    "shared cards, menu rows and separators must use common geometry",
)

violations = []
type_violations = []
type_pattern = re.compile(
    r"pf\((?:21|17\.5|16\.5|16|15\.5|13\.5|12\.5|12|13),"
    r"\s*\.(?:semibold|medium)\)|"
    r"pf\((?:21|17\.5|16\.5|15\.5|13\.5|12\.5)\)"
)
height_pattern = re.compile(
    r"\.frame\(height:\s*(?:8|20|24|28|30|32|36|38|40|42|44|48|50|52|54|56|60|64|72|82)(?:\.0)?\)"
)
spacing_pattern = re.compile(
    r"\.padding\(\.(?:horizontal|vertical|top|bottom|leading|trailing),"
    r"\s*(?:4|8|12|16|20|24|32)\)|"
    r"\.padding\((?:4|8|12|16|20|24|32)\)|"
    r"\b(?:VStack|HStack|LazyVStack|LazyHStack)\(spacing:\s*"
    r"(?:4|8|12|16|20|24|32)"
)
for path in SOURCES.glob("*.swift"):
    if path.name == "DesignSystem.swift":
        continue
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    for index, line in enumerate(lines, start=1):
        if type_pattern.search(line):
            type_violations.append(f"{path.name}:{index}")
        if height_pattern.search(line):
            type_violations.append(f"{path.name}:{index} [height]")
        if spacing_pattern.search(line):
            type_violations.append(f"{path.name}:{index} [spacing]")
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
    not type_violations,
    "shared type roles must be used instead of page-level pf sizes: "
    + ", ".join(type_violations[:12]),
)
press_violations = [
    path.name
    for path in SOURCES.glob("*.swift")
    if path.name != "DesignSystem.swift"
    and re.search(r"struct \w+PressStyle: ButtonStyle", path.read_text(encoding="utf-8"))
]
require(
    not press_violations,
    "all press feedback styles must live in DesignSystem.swift: "
    + ", ".join(press_violations[:12]),
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
    re.search(r"(?:UI)?Color\(hex:\s*0x[0-9A-Fa-f]{6}", PROFILE) is None
    and re.search(r"(?:UI)?Color\(hex:\s*0x[0-9A-Fa-f]{6}", CONTACTS) is None
    and re.search(r"(?:UI)?Color\(hex:\s*0x[0-9A-Fa-f]{6}", CHATS) is None
    and "AppPalette" in CHATS
    and "OrbitTheme.gold" in CONTACTS
    and "OrbitTheme.blue" in CONTACTS
    and "OrbitTheme.male" in CONTACTS
    and "OrbitTheme.female" in CONTACTS,
    "migrated page-level colors must use semantic theme tokens",
)
require(
    "python3 tools/verify-design-consistency.py" in WORKFLOW,
    "design consistency regression must run in the iOS gate",
)

print("design-consistency: passed")
