#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MOSAIC = (ROOT / "Sources" / "MultiImageMosaic.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
NATIVE = (ROOT / "Sources" / "NativeChatMediaRowCell.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("multi-image mosaic verification failed: " + message)


require(
    "let gap: CGFloat = 2.5" in CHAT
    and ".frame(width: width, height: 188)" in CHAT
    and "RoundedRectangle(cornerRadius: 17" in CHAT
    and "let tileWidth = (width - gap) / 2" in CHAT
    and ".frame(width: tileWidth, height: 172)" in CHAT
    and "let strip = Array(paths.dropFirst().prefix(3))" in CHAT
    and ".frame(width: width, height: 156)" in CHAT
    and ".frame(width: tileWidth, height: 76)" in CHAT
    and 'Text("+\\(total - strip.count - 1)")' in CHAT,
    "SwiftUI image and multi-image containers must match the 11/20 geometry",
)
require(
    "let gap: CGFloat = 2.5" in NATIVE
    and "height: 156" in NATIVE
    and "height: 76" in NATIVE
    and "if paths.count <= 1 { return 188 }" in NATIVE
    and "if paths.count == 2 { return 172 }" in NATIVE
    and "return 234.5" in NATIVE
    and 'badgeLabel.text = "+\\(paths.count - stripCount - 1)"' in NATIVE,
    "native single and multi-image rows must match the 11/20 containers",
)
require(
    "python3 tools/verify-multi-image-mosaic.py" in WORKFLOW,
    "multi-image mosaic regression must run in the iOS gate",
)

print("multi-image-mosaic: passed")
