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
    "contrastScrim.opacity(effectiveDark ? 0.24 : 0.20)" in CHAT
    and "contrastScrim.opacity(effectiveDark ? 0.14 : 0.11)" in CHAT,
    "top and bottom chrome need a restrained contrast falloff over wallpapers",
)
require(
    "private struct ChatCleanEdgeMask" in CHAT
    and "scheme == .light && !topBarUsesLightInk" in CHAT
    and "scheme == .light && !composerUsesLightInk" in CHAT
    and "ChatCleanEdgeMask(" in CHAT,
    "light chat chrome must use a clean edge surface instead of layered wallpaper effects",
)
require(
    "NativeGlassHeaderMaterial(\n"
    "                            forcedDark: composerUsesLightInk" in CHAT
    and "Color.black.opacity(0.28)" in CHAT
    and "Color.white.opacity(0.76)" in CHAT,
    "composer fields must keep one refined native-glass surface on every wallpaper",
)
require(
    "NativeGlassHeaderMaterial(forcedDark: lightInk)" in CHAT
    and "capsule.fill(lightInk" in CHAT
    and "ChatTopGlassBackdrop(lightInk: topBarUsesLightInk)" in CHAT,
    "top header glass and icon capsules must switch to dark material over black wallpapers",
)
require(
    CHAT.count("if !path.isEmpty { return scheme == .dark }") >= 2
    and "backgroundSamplePath == path, let backgroundTopLuminance" in CHAT
    and "backgroundSamplePath == path, let backgroundBottomLuminance" in CHAT,
    "wallpaper changes must ignore stale samples and default safely by appearance mode",
)
require(
    "NativeGlassHeaderMaterial(forcedDark:" in CHAT
    and ".glassEffect(.regular.interactive(), in: capsule)" in CHAT,
    "contrast protection must preserve the existing native glass controls",
)
require(
    "Color(hex: 0xEFF5F1).opacity(0.92)" in CHAT
    and "Color(hex: 0x35413C)" in CHAT
    and "composerUtilityInk.opacity(0.82)" in CHAT,
    "composer icons and placeholder must use the refined adaptive ink",
)
require(
    "python3 tools/verify-chat-chrome-contrast.py" in WORKFLOW,
    "chat chrome contrast regression must run in the iOS gate",
)

print("chat-chrome-contrast: passed")
