#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCES = "\n".join(
    path.read_text(encoding="utf-8")
    for path in sorted((ROOT / "Sources").glob("*.swift"))
)
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("no-glass verification failed: " + message)


for token in (
    ".ultraThinMaterial",
    ".thinMaterial",
    ".regularMaterial",
    ".glassEffect(",
):
    require(token not in SOURCES, "glass API remains: " + token)

NAV = (ROOT / "Sources" / "NavGlass.swift").read_text(encoding="utf-8")
frosted = NAV.split("struct NativeFrostedHeaderMaterial", 1)[1].split(
    "#endif", 1
)[0]
require(
    "UIBlurEffect(style: scheme == .dark" in frosted
    and "UIVisualEffectView" in frosted
    and "UIBlurEffect" not in frosted.replace(
        "UIBlurEffect(style: scheme == .dark", ""
    ),
    "native system material is allowed only for the scroll-edge mask",
)
require(
    SOURCES.count("UIGlassEffect(") == 1
    and "struct NativeMediaGlassMaterial" in NAV
    and "UIGlassEffect(style: .regular)" in NAV
    and "struct NativeMediaGlassSurface" in NAV,
    "media controls may use exactly one native system glass component",
)

require(
    "C.floatingSurface" in SOURCES
    and "C.controlSurface" in SOURCES
    and "appearance.configureWithOpaqueBackground()" in SOURCES
    and "appearance.backgroundEffect = nil" in SOURCES,
    "solid floating, control and tab surfaces must replace glass",
)
require(
    "python3 tools/verify-no-glass.py" in WORKFLOW,
    "the no-glass regression must run in the iOS gate",
)

print("no-glass: passed")
