#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")
INFO = (ROOT / "Info.plist").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)
MAC_BUILD = (ROOT / "mac-build.sh").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("no-splash verification failed: " + message)


for relative in (
    "Sources/SplashView.swift",
    "tools/verify-splash-premium.py",
    "splash.original-1260x2021.png",
    "splash.planet-1290x2796.jpg",
):
    require(
        not (ROOT / relative).exists(),
        "obsolete startup asset must be deleted: " + relative,
    )

require(
    "SplashView" not in APP
    and "LaunchView" not in APP
    and "splashDone" not in APP
    and "if !app.booting {" in APP,
    "the app must render its first real destination directly after boot",
)
require(
    "<key>UILaunchScreen</key>" in INFO
    and "<key>UIColorName</key><string>LaunchBg</string>" in INFO
    and "UIImageName" not in INFO
    and "LaunchLogo" not in INFO,
    "the required native launch surface must be a blank solid colour without branding",
)
require(
    "LaunchLogo" not in WORKFLOW
    and "LaunchLogo" not in MAC_BUILD
    and "python3 tools/verify-no-splash-page.py" in WORKFLOW,
    "build pipelines must not package or reintroduce the startup logo page",
)

print("no-splash-page: passed")
