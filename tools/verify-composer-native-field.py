#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("composer native field verification failed: " + message)


require(
    "private var composerFieldShape: RoundedRectangle" in CHAT
    and "NativeGlassHeaderMaterial(forcedDark: true)" in CHAT
    and "Color(uiColor: .systemBackground).opacity(0.97)" in CHAT
    and ".clipShape(composerFieldShape)" in CHAT,
    "composer field must use clean light mode and native glass over dark wallpapers",
)
require(
    "composerFieldShape.fill(.regularMaterial)" not in CHAT,
    "composer field must not fall back to an opaque material-only surface",
)
require(
    "Color.white.opacity(0.18)" in CHAT
    and "Color.black.opacity(0.055)" in CHAT,
    "composer field needs the subtle native hairline",
)

print("composer-native-field: passed")
