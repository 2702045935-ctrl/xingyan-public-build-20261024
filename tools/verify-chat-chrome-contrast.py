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
    "contrastScrim.opacity(effectiveDark ? 0.25 : 0.22)" in CHAT
    and "contrastScrim.opacity(effectiveDark ? 0.14 : 0.12)" in CHAT,
    "top and bottom chrome need a strong-to-transparent contrast falloff",
)
require(
    "NativeGlassHeaderMaterial(forcedDark: composerUsesLightInk)" in CHAT
    and ".opacity(composerUsesLightInk ? 0.42 : 0.32)" not in CHAT
    and "NativeGlassHeaderMaterial(forcedDark: composerUsesLightInk)" in CHAT,
    "composer field backing must use one opaque wallpaper-aware surface",
)
require(
    "NativeGlassHeaderMaterial(forcedDark: lightInk)" in CHAT
    and "capsule.fill(lightInk" in CHAT
    and "ChatTopGlassBackdrop(lightInk: topBarUsesLightInk)" in CHAT
    and "scheme == .light && !hasPickedChatWallpaper" in CHAT
    and "scheme == .light && hasPickedChatWallpaper" in CHAT
    and "private var hasPickedChatWallpaper: Bool" in CHAT,
    "light wallpaper must stay out of top and bottom chat masks",
)
require(
    CHAT.count("if !path.isEmpty { return true }") >= 2,
    "unsampled custom wallpapers must default to light chrome instead of system light ink",
)
require(
    "NativeGlassHeaderMaterial(forcedDark:" in CHAT
    and "capsule.fill(lightInk" in CHAT
    and ".glassEffect(" not in CHAT,
    "contrast protection must use opaque adaptive controls",
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
