#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("composer native field verification failed: " + message)


require(
    "private var composerFieldShape: RoundedRectangle" in CHAT
    and "NativeGlassHeaderMaterial(forcedDark: composerUsesLightInk)" in CHAT
    and ".clipShape(composerFieldShape)" in CHAT,
    "composer field must use the opaque adaptive surface",
)
require(
    "composerFieldShape.fill(.regularMaterial)" not in CHAT
    and "composerFieldShape\n+                            .fill((composerUsesLightInk" not in CHAT,
    "composer field must not use glass or a translucent tint",
)
require(
    "Color.white.opacity(0.18)" in CHAT
    and "Color.black.opacity(0.085)" in CHAT,
    "composer field needs the subtle native hairline",
)

print("composer-native-field: passed")
