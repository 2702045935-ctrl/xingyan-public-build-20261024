#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MOSAIC = (ROOT / "Sources" / "MultiImageMosaic.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
MEDIA = (ROOT / "Sources" / "ChatMediaBubbles.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("multi-image mosaic verification failed: " + message)


require(
    "static let gap: CGFloat = 3" in MOSAIC
    and "if total <= 4 { return max(0, total) }" in MOSAIC
    and "return 3\n    }" in MOSAIC
    and "if total == 2" in MOSAIC
    and "let heroW = floor(innerW * 0.64)" in MOSAIC
    and "let leftW = floor((bounds.width - gap) / 2)" in MOSAIC
    and "let topH = floor((bounds.height - gap) / 2)" in MOSAIC,
    "the shared mosaic must use two-up, hero, and 2x2 compositions",
)
require(
    "let strip = Array(paths.dropFirst().prefix(3))" in CHAT
    and 'Text("+\\(total - strip.count - 1)")' in CHAT
    and "RemoteImage(path: paths[0], maxSide: 1200)" in CHAT
    and "private func stackedMultiImageGlass" in CHAT
    and ".rotationEffect(.degrees(-2.8), anchor: .bottomLeading)" in CHAT
    and ".rotationEffect(.degrees(-1.35), anchor: .bottomLeading)" in CHAT
    and ".rotationEffect(.degrees(1.05), anchor: .bottomTrailing)" in CHAT
    and CHAT.count(".rotation3DEffect(") >= 3
    and "perspective: 0.52" in CHAT
    and CHAT.count(".frame(width: plateW, height: plateH)") >= 3
    and "NativeMediaGlassSurface(" in CHAT,
    "SwiftUI multi-image messages must render the shared adaptive mosaic",
)
require(
    "MultiImageMosaic.containerSize(for: images.count, width: 229)" in MEDIA
    and "MultiImageMosaic.frames(" in MEDIA
    and "SendingVideoBubble" in MEDIA,
    "pending media rows must use the same adaptive mosaic geometry",
)
require(
    "python3 tools/verify-multi-image-mosaic.py" in WORKFLOW,
    "multi-image mosaic regression must run in the iOS gate",
)

print("multi-image-mosaic: passed")
