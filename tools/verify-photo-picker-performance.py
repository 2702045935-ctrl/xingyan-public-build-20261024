#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PICKERS = (ROOT / "Sources" / "Pickers.swift").read_text(encoding="utf-8")
WALLPAPER = (ROOT / "Sources" / "ChatBackgroundSheet.swift").read_text(
    encoding="utf-8"
)
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("photo-picker-performance verification failed: " + message)


start = PICKERS.index("struct PhotoPicker")
end = PICKERS.index("enum AlbumPicker", start)
block = PICKERS[start:end]
require(
    "var maxSide: CGFloat = 2048" in block
    and "provider.loadDataRepresentation(" in block
    and "RemoteImage.downsampled(data, maxSide: decodeSide)" in block
    and "DispatchQueue.global(qos: .userInitiated).async" in block,
    "single-photo picking must downsample source data off the main thread",
)
require(
    block.index("provider.loadDataRepresentation(")
    < block.index("provider.loadObject(ofClass: UIImage.self)"),
    "full UIImage decoding must only be a fallback after data decoding",
)
require(
    WALLPAPER.count(
        "PhotoPicker(maxSide: chatWallpaperDecodeSide()) { image in"
    ) >= 2,
    "wallpaper picks must request the native wallpaper decode size",
)
require(
    "python3 tools/verify-photo-picker-performance.py" in WORKFLOW,
    "shared photo picker performance regression must run in the iOS gate",
)

print("photo-picker-performance: passed")
