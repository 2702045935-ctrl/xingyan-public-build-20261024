#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPLASH = (ROOT / "Sources" / "SplashView.swift").read_text(encoding="utf-8")
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")
INFO = (ROOT / "Info.plist").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
ADMIN = (ROOT / "server" / "public" / "admin.html").read_text(encoding="utf-8")
VIEW = SPLASH.split("struct SplashView: View", 1)[1]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("premium splash verification failed: " + message)


require(
    "private var launchCanvas: some View" in VIEW
    and "StarLaunchBackdrop" not in VIEW
    and "LaunchSilkField" not in VIEW
    and "StarLaunchMark" not in VIEW
    and "shimmering" not in VIEW
    and "breathing" not in VIEW,
    "legacy launch views must be removed instead of remaining as dormant fallbacks",
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
    "SplashView()" in APP
    and "struct LaunchView: View" in APP
    and "SplashView()" in APP.split("struct LaunchView: View", 1)[1].split(
        "struct LoginViewOld", 1
    )[0]
    and "splashImage" not in APP
    and "StarLaunchMark" not in APP,
    "cold launch and the booting fallback must use the same premium launch screen",
)
require(
    "<key>UIColorName</key><string>LaunchBg</string>" in INFO
    and "<key>UIImageName</key><string>LaunchLogo</string>" in INFO,
    "the native iOS launch screen must carry the brand background and centered icon",
)
require(
    "LaunchLogo.imageset" in WORKFLOW
    and "LaunchLogo@3x.png" in WORKFLOW,
    "the iOS build must package the native LaunchLogo asset",
)
require(
    "splash.jpg" not in WORKFLOW,
    "the legacy launch bitmap must not be packaged anymore",
)
require(
    "body.splash" not in SERVER
    and "iconPreview-splash" not in ADMIN
    and "data-upload=\"splash\"" not in ADMIN,
    "the obsolete remote launch-image controls must be removed from the server and admin UI",
)
require(
    "python3 tools/verify-splash-premium.py" in WORKFLOW,
    "premium launch screen regression must run in the iOS gate",
)

print("splash-premium: passed")
