#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("composer native field verification failed: " + message)


require(
    "private var composerFieldShape: RoundedRectangle" in CHAT
    and "NativeMediaGlassSurface(\n                            shape: AnyShape(composerFieldShape),\n                            showsEdge: false\n                        )"
    in CHAT
    and "composerUsesLightInk ? .dark : .light" in CHAT
    and ".clipShape(composerFieldShape)" in CHAT,
    "composer field must use a native floating glass capsule",
)
require(
    "if panel != .none && !(panel == .emoji && emojiPanelExpanded)"
    in CHAT
    and "radius: 9,\n                        x: 0,\n                        y: 4" in CHAT,
    "the composer must float without the legacy full-width bottom mask",
)
require(
    "Color.white.opacity(0.62)" in CHAT
    and "Color.white.opacity(0.16)" in CHAT,
    "composer glass needs a restrained specular hairline",
)

print("composer-native-field: passed")
