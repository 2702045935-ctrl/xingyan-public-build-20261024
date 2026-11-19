#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat chrome contrast verification failed: " + message)


require(
    "let contrastScrim = effectiveDark ? Color.black : Color.white" in CHAT,
    "wallpaper edge masks must choose a scrim opposite to the selected ink",
)
require(
    "contrastScrim.opacity(effectiveDark ? 0.30 : 0.26)" in CHAT
    and "contrastScrim.opacity(effectiveDark ? 0.18 : 0.15)" in CHAT,
    "top and bottom chrome need a strong-to-transparent contrast falloff",
)
require(
    "(composerUsesLightInk ? Color.black : Color.white)" in CHAT
    and ".opacity(composerUsesLightInk ? 0.28 : 0.32)" in CHAT,
    "composer field backing must follow wallpaper luminance, not system appearance",
)
require(
    "NativeGlassHeaderMaterial()" in CHAT
    and ".glassEffect(.regular.interactive(), in: capsule)" in CHAT,
    "contrast protection must preserve the existing native glass controls",
)
require(
    "Color.white.opacity(0.90)" in CHAT
    and "Color(hex: 0x3E4A52)" in CHAT
    and "composerUtilityInk.opacity(0.82)" in CHAT,
    "composer utility icons and placeholder must retain readable contrast",
)
require(
    "python3 tools/verify-chat-chrome-contrast.py" in WORKFLOW,
    "chat chrome contrast regression must run in the iOS gate",
)

print("chat-chrome-contrast: passed")
