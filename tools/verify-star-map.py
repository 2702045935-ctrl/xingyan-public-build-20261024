#!/usr/bin/env python3
import plistlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORLD = (ROOT / "Sources" / "StarWorld3D.swift").read_text(encoding="utf-8")
DISCOVER = (ROOT / "Sources" / "DiscoverView.swift").read_text(encoding="utf-8")
MAIN_TAB = (ROOT / "Sources" / "MainTab.swift").read_text(encoding="utf-8")
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)
INFO = plistlib.loads((ROOT / "Info.plist").read_bytes())


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("star world verification failed: " + message)


require(
    not (ROOT / "Sources" / "StarMapView.swift").exists(),
    "the retired 2D world page must be removed from the client target",
)
require(
    "struct StarWorldExperienceView: View" in WORLD
    and "StarWorldSceneView(" in WORLD
    and "StarWorldLoadingOverlay(destination: loadingMap)" in WORLD
    and "StarWorldUSDZScene.preloadIfNeeded()" in WORLD
    and "beginTravel(to destination: StarWorldMap)" in WORLD,
    "the world entry must use the immersive SceneKit experience",
)
require(
    "if mountedTabs.contains(3) {" in MAIN_TAB
    and "StarWorldExperienceView(embedded: true)" in MAIN_TAB
    and "if mountedTabs.contains(3) { DiscoverView() }" not in MAIN_TAB
    and "StarWorldDirectoryView" not in WORLD
    and ".statusBarHidden(true)" not in WORLD
    and MAIN_TAB.count(".statusBarHidden(false)") == 5
    and "DiscoverView()" in WORLD,
    "the world tab must mount the immersive world while keeping all status bars visible",
)
require(
    ".opacity(entered ? 1 : 0.01)" not in WORLD
    and ".scaleEffect(entered ? 1 : 0.92)" not in WORLD
    and "value: entered" not in WORLD,
    "the world must render directly instead of revealing a legacy first page",
)
require(
    "SCNView" in WORLD
    and "SCNSceneRendererDelegate" in WORLD
    and "onFirstFrame" in WORLD
    and "resetViewport(for: map)" in WORLD,
    "the world must own its native 3D first frame and camera reset",
)
require(
    'grouped.flatMap { $0 }.filter { $0.action != "map" }' in DISCOVER
    and 'case "map": ComingSoonView(title: Tr("星轨地图"))' in DISCOVER
    and "StarWorldExperienceView()" not in DISCOVER
    and "'map'" in SERVER
    and "parts[0] === 'ui-manifest'" in SERVER,
    "the legacy world directory must not compete with the direct 3D world tab",
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
