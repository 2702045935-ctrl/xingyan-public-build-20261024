#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NAV = (ROOT / "Sources" / "NavGlass.swift").read_text(encoding="utf-8")
CORE = (ROOT / "Sources" / "Core.swift").read_text(encoding="utf-8")
VIDEO = (ROOT / "Sources" / "ChatMediaBubbles.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("media viewer glass verification failed: " + message)


require(
    "struct NativeGlassControlMaterial: View" in NAV
    and "var shape: AnyShape = AnyShape(Capsule(style: .continuous))" in NAV
    and "shape\n            .fill(C.floatingSurface)" in NAV
    and "shape.stroke(C.hairline" in NAV
    and "glassEffect(" not in NAV
    and "UIVisualEffectView" not in NAV
    and "shape: AnyShape(Circle())" in NAV
    and "interactive: true" in NAV,
    "viewer controls must share the opaque floating surface",
)
require(
    CORE.count("NativeGlassControlMaterial()") >= 2
    and "GlassBackground(\n                                shape: Capsule(style: .continuous)"
    not in CORE
    and "GlassBackground(shape: Capsule(style: .continuous), shadow: true)" not in CORE,
    "photo viewer count and action bar must use opaque controls",
)
require(
    "shape: AnyShape(\n                                RoundedRectangle(" in VIDEO
    and "NativeGlassControlMaterial(\n                                        interactive: true" in VIDEO
    and "NativeGlassControlMaterial()" in VIDEO
    and "GlassBackground(" not in VIDEO,
    "video viewer scrubber, speed and message controls must use opaque controls",
)
require(
    "python3 tools/verify-media-viewer-glass.py" in WORKFLOW,
    "media viewer glass regression must run in the iOS gate",
)

print("media-viewer-glass: passed")
