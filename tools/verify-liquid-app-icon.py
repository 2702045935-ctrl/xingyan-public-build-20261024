#!/usr/bin/env python3
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)
PREPARER = (ROOT / "tools" / "prepare-liquid-icon.sh").read_text(encoding="utf-8")
INFO = (ROOT / "Info.plist").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("liquid app icon verification failed: " + message)


require(
    "<key>CFBundleIconName</key>" in INFO
    and "<string>AppIcon</string>" in INFO,
    "the bundle must select the AppIcon asset catalog instead of only loose PNGs",
)
require(
    "bash tools/prepare-liquid-icon.sh Assets.xcassets" in WORKFLOW
    and "--app-icon AppIcon" in WORKFLOW
    and "--include-all-app-icons" in WORKFLOW,
    "Xcode 26 must compile the layered iOS icon catalog and all generated sizes",
)
require(
    '"value": "dark"' in PREPARER
    and '"value": "tinted"' in PREPARER
    and "AppIcon-Light.png" in PREPARER
    and "AppIcon-Dark.png" in PREPARER
    and "AppIcon-Tinted.png" in PREPARER,
    "light, dark and tinted Liquid Glass appearances must be present",
)
for name in (
    "app-icon-starorbit-glass-1024.png",
    "app-icon-starorbit-glass-dark-1024.png",
    "app-icon-starorbit-glass-tinted-1024.png",
):
    image = Image.open(ROOT / name)
    require(image.size == (1024, 1024), f"{name} must be 1024x1024")

print("liquid-app-icon: passed")
