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
    "MultiImageMosaic.visibleCount(for: total)" in CHAT
    and "MultiImageMosaic.frames(" in CHAT
    and 'Text("+\\(total - visible)")' in CHAT
    and "RemoteImage(path: paths[index], maxSide: 1200)" in CHAT
    and "RoundedRectangle(cornerRadius: outerRadius" in CHAT,
    "SwiftUI multi-image messages must render the shared adaptive mosaic",
)
require(
    "MultiImageMosaic.visibleCount(for: paths.count)" in NATIVE
    and "MultiImageMosaic.frames(count: paths.count, in: body)" in NATIVE
    and "badgeLabel.text = \"+\\(paths.count - visible)\"" in NATIVE
    and "view.layer.cornerRadius = min(12" in NATIVE
    and "containerSize(for: paths.count, width: 229)" in NATIVE,
    "native media rows must use the same mosaic geometry without per-row blur",
)
require(
    "python3 tools/verify-multi-image-mosaic.py" in WORKFLOW,
    "multi-image mosaic regression must run in the iOS gate",
)

print("multi-image-mosaic: passed")
