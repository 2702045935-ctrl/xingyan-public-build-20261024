#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("composer native field verification failed: " + message)


require(
    "private var composerFieldShape: RoundedRectangle" in CHAT
    and "composerFieldShape.fill(.regularMaterial)" in CHAT
    and "Color(uiColor: .secondarySystemBackground)" in CHAT,
    "composer field must use native material and system background",
)
require(
    "GlassBackground(\n                            shape: fieldShape" not in CHAT,
    "composer field must not retain the old custom glass stack",
)
require(
    "Color.primary.opacity(0.085)" in CHAT,
    "composer field needs the subtle native hairline",
)

print("composer-native-field: passed")
