#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NAV = (ROOT / "Sources" / "NavGlass.swift").read_text(encoding="utf-8")
CORE = (ROOT / "Sources" / "Core.swift").read_text(encoding="utf-8")
VIDEO = (ROOT / "Sources" / "ChatMediaBubbles.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
COMPOSER = (ROOT / "Sources" / "ChatComposerField.swift").read_text(encoding="utf-8")
PANELS = (ROOT / "Sources" / "Panels.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("media viewer glass verification failed: " + message)


require(
    "struct NativeMediaGlassMaterial" in NAV
    and "UIGlassEffect(style: .regular)" in NAV
    and "struct NativeMediaGlassSurface: View" in NAV
    and "var shape: AnyShape = AnyShape(Capsule(style: .continuous))" in NAV
    and "glassEffect(" not in NAV
    and "struct NativeMediaGlassCircleBackground" in NAV,
    "viewer controls must share one native system glass component",
)
require(
    CORE.count("NativeMediaGlassSurface()") >= 2
    and "NativeMediaGlassCircleBackground()" in CORE
    and "GlassBackground(\n                                shape: Capsule(style: .continuous)"
    not in CORE
    and "GlassBackground(shape: Capsule(style: .continuous), shadow: true)" not in CORE,
    "photo viewer count and action bar must use native system glass",
)
require(
    "NativeMediaGlassSurface(\n                            shape: AnyShape(\n                                RoundedRectangle(" in VIDEO
    and "NativeMediaGlassSurface(\n                                        shape: AnyShape(Capsule(style: .continuous)),\n                                        interactive: true" in VIDEO
    and "NativeMediaGlassSurface()" in VIDEO
    and "NativeMediaGlassCircleBackground()" in VIDEO
    and "GlassBackground(" not in VIDEO,
    "video viewer scrubber, speed and message controls must use native system glass",
)
require(
    "NativeGlassControlMaterial()" in CHAT
    and CHAT.count("NativeMediaGlassSurface(") >= 2
    and "NativeMediaGlassSurface(shape: AnyShape(Rectangle()))" in CHAT
    and "showsEdge: false" in CHAT,
    "chat must keep lightweight row glass while native glass stays on global controls",
)
require(
    "GlassBackground(" not in COMPOSER
    and COMPOSER.count("NativeMediaGlassSurface(") >= 4,
    "full-screen composer controls must use native system glass",
)
require(
    "GlassBackground(" not in PANELS
    and PANELS.count("NativeMediaGlassSurface(") >= 3,
    "emoji and attachment panels must use native system glass",
)
require(
    "python3 tools/verify-media-viewer-glass.py" in WORKFLOW,
    "media viewer glass regression must run in the iOS gate",
)

print("media-viewer-glass: passed")
