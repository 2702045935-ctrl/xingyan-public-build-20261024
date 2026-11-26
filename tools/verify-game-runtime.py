#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUNTIME = (ROOT / "Sources" / "GameRuntime.swift").read_text(encoding="utf-8")
GAMES = (ROOT / "Sources" / "GamesPageView.swift").read_text(encoding="utf-8")
MINIAPPS = (ROOT / "Sources" / "MiniApps.swift").read_text(encoding="utf-8")
WORLD = (ROOT / "Sources" / "StarWorld3D.swift").read_text(encoding="utf-8")
USDZ = (ROOT / "Sources" / "StarWorldUSDZScene.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("game-runtime verification failed: " + message)


require(
    "WKProcessPool" in RUNTIME
    and "GameRuntimeWarmup" in RUNTIME
    and "withThrowingTaskGroup" in RUNTIME
    and "delaysContentTouches = false" in RUNTIME
    and "devicePixelRatio" in RUNTIME
    and "powerPreference" in RUNTIME
    and "desynchronized" in RUNTIME,
    "the web runtime must reuse its process, prewarm, bound image load and cap render cost",
)
require(
    "GameRuntimeConfiguration.make()" in GAMES
    and "GameRuntimeConfiguration.configure(v)" in GAMES
    and "GameRuntimeWarmup.warm()" in GAMES
    and "GameRuntimeAssets.download(" in GAMES
    and "gamePerformanceJS" not in GAMES,
    "game pages must use the shared runtime and bounded asset loader",
)
require(
    "GameRuntimeConfiguration.make()" in MINIAPPS
    and "GameRuntimeConfiguration.configure(v)" in MINIAPPS
    and "GameRuntimeWarmup.warm()" in MINIAPPS
    and "GameRuntimeAssets.download(" in MINIAPPS,
    "mini apps must use the same warm runtime and asset pipeline",
)
require(
    "@Binding var yaw" not in WORLD
    and "@Binding var pitch" not in WORLD
    and ".id(\"\\(activeMap.rawValue)-\\(avatarProfile.hashValue)\")" not in WORLD
    and "func handlePan(" in WORLD
    and "func applyCamera(" in WORLD
    and "func applyRenderQuality(" in WORLD
    and "view.antialiasingMode = constrained ? .none : .multisampling2X" in WORLD
    and "view.rendersContinuously = false" in WORLD
    and "onFirstFrame: finishWorldLoad" in WORLD
    and "didRenderScene" in WORLD
    and "DispatchQueue.main.asyncAfter(deadline: .now() + 1.05)" not in WORLD
    and "DispatchQueue.main.asyncAfter(deadline: .now() + 0.72)" not in WORLD
    and "StarWorldUSDZScene.preloadIfNeeded()" in WORLD,
    "the SceneKit runtime must keep drag/camera work native and reuse the scene view",
)
require(
    "NSCache<NSURL, SCNScene>" in USDZ
    and "static func preloadIfNeeded()" in USDZ
    and "rootNode.clone()" in USDZ
    and "shadowMapSize = CGSize(width: 1024, height: 1024)" in USDZ,
    "world assets must be cached, cloned and rendered within a bounded quality budget",
)
require(
    "python3 tools/verify-game-runtime.py" in WORKFLOW,
    "the game runtime performance gate must run in the iOS build workflow",
)

print("game-runtime: passed")
