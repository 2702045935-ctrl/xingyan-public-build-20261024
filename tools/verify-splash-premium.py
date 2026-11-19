#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPLASH = (ROOT / "Sources" / "SplashView.swift").read_text(encoding="utf-8")
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)
VIEW = SPLASH.split("struct SplashView: View", 1)[1].split(
    "struct StarLaunchBackdrop", 1
)[0]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("premium splash verification failed: " + message)


require(
    "private var launchCanvas: some View" in VIEW
    and "StarLaunchBackdrop" not in VIEW
    and "LaunchSilkField" not in VIEW
    and "shimmering" not in VIEW
    and "breathing" not in VIEW,
    "launch screen must use a clean brand canvas instead of stacked decorative effects",
)
require(
    "AppIconImage.image" in VIEW
    and 'Text("让每一句真心，都有回应")' in VIEW
    and "OrbitTheme.jadeDeep" in VIEW,
    "launch screen must prioritize icon, wordmark, tagline and the fixed brand palette",
)
require(
    "accessibilityReduceMotion" in VIEW
    and "reduceMotion ? nil" in VIEW,
    "launch motion must respect Reduce Motion",
)
require(
    "SplashView(remote: app.splashImage)" in APP
    and "StarLaunchMark(size: 74, breathing: false)" in APP,
    "the new first-launch screen and existing fallback launch view must both remain mounted",
)
require(
    "python3 tools/verify-splash-premium.py" in WORKFLOW,
    "premium launch screen regression must run in the iOS gate",
)

print("splash-premium: passed")
