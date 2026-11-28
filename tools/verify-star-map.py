#!/usr/bin/env python3
import plistlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORLD = (ROOT / "Sources" / "StarWorldSystemView.swift").read_text(encoding="utf-8")
MAIN_TAB = (ROOT / "Sources" / "MainTab.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)
INFO = plistlib.loads((ROOT / "Info.plist").read_bytes())


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("star world verification failed: " + message)


for retired in (
    "StarWorld3D.swift",
    "StarWorldLoadingOverlay.swift",
    "StarWorldPlazaScene.swift",
    "StarWorldUSDZScene.swift",
):
    require(
        not (ROOT / "Sources" / retired).exists(),
        f"retired world implementation must be deleted: {retired}",
    )

require(
    "struct StarWorldSystemView: View" in WORLD
    and "private enum StarWorldRoute" in WORLD
    and 'Text(Tr("世界"))' in WORLD
    and 'sectionHeader(Tr("内容"))' in WORLD
    and 'sectionHeader(Tr("工具"))' in WORLD
    and ".listStyle(.insetGrouped)" in WORLD
    and ".environment(\\.defaultMinListRowHeight, 52)" in WORLD
    and "NavigationStack {" in WORLD,
    "the world tab must be a unified inset-grouped system hub",
)
require(
    all(marker not in WORLD for marker in (
        "SceneKit",
        "SCNView",
        "广场",
        "房间",
        "3D",
        "StarWorldLoadingOverlay",
    )),
    "the new world page must not retain plaza, room, SceneKit or loading-scene code",
)
require(
    "if mountedTabs.contains(3) {" in MAIN_TAB
    and "StarWorldSystemView(embedded: true)" in MAIN_TAB
    and "StarWorldExperienceView" not in MAIN_TAB
    and MAIN_TAB.count(".statusBarHidden(false)") == 5,
    "the world tab must mount the new system page with visible system status bars",
)
require(
    "UIBackgroundModes" in INFO,
    "the app must retain the navigation-capable background contract",
)
require(
    "python3 tools/verify-star-map.py" in WORKFLOW,
    "world regression must run in the iOS gate",
)

print("star-world: passed")
