#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("composer native field verification failed: " + message)


require(
    "private var composerFieldShape: RoundedRectangle" in CHAT
    and "NativeGlassHeaderMaterial()" in CHAT
    and ".clipShape(composerFieldShape)" in CHAT,
    "composer field must use the native Liquid Glass surface",
)
require(
    "composerFieldShape.fill(.regularMaterial)" not in CHAT,
    "composer field must not fall back to an opaque material-only surface",
)
require(
    "Color.primary.opacity(0.085)" in CHAT,
    "composer field needs the subtle native hairline",
)

print("composer-native-field: passed")
