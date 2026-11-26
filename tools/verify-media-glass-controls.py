#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GLASS = (ROOT / "Sources" / "NavGlass.swift").read_text(encoding="utf-8")
CORE = (ROOT / "Sources" / "Core.swift").read_text(encoding="utf-8")
MEDIA = (ROOT / "Sources" / "ChatMediaBubbles.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("media glass verification failed: " + message)


require(
    "struct MediaViewerGlassCircleBackground: View" in GLASS
    and ".glassEffect(" in GLASS
    and "RadialGradient(" in GLASS
    and "Color.white.opacity(0.66)" in GLASS
    and "shape\n                    .inset(by: 1.35)" in GLASS,
    "media viewer glass must use native glass plus specular highlights, edge light, and an inner rim",
)
require(
    CORE.count("MediaViewerGlassCircleBackground()") >= 1
    and MEDIA.count("MediaViewerGlassCircleBackground()") >= 4,
    "photo and video viewer controls must share the refined media glass treatment",
)
require(
    "python3 tools/verify-media-glass-controls.py" in WORKFLOW,
    "media glass controls must run in the iOS gate",
)

print("media-glass-controls: passed")
