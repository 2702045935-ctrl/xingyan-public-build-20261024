#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUNTIME = (ROOT / "Sources" / "GameRuntime.swift").read_text(encoding="utf-8")
GAMES = (ROOT / "Sources" / "GamesPageView.swift").read_text(encoding="utf-8")
MINIAPPS = (ROOT / "Sources" / "MiniApps.swift").read_text(encoding="utf-8")
WORLD = (ROOT / "Sources" / "StarWorldSystemView.swift").read_text(encoding="utf-8")
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
    not (ROOT / "Sources" / "StarWorld3D.swift").exists()
    and not (ROOT / "Sources" / "StarWorldUSDZScene.swift").exists()
    and "SceneKit" not in WORLD
    and "StarWorldSystemView: View" in WORLD,
    "the retired world scene must be removed while games retain the web runtime",
)
require(
    "python3 tools/verify-game-runtime.py" in WORKFLOW,
    "the game runtime performance gate must run in the iOS build workflow",
)

print("game-runtime: passed")
