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
    "private struct NativeChatFrostedEdgeMaterial" in CHAT
    and ".systemUltraThinMaterialDark" in CHAT
    and ".systemUltraThinMaterialLight" in CHAT
    and ".systemThinMaterialDark" in CHAT
    and ".systemThinMaterialLight" in CHAT
    and "private struct ChatFrostedEdgeMask" in CHAT
    and "let base: Color" in CHAT
    and "if reduceTransparency" in CHAT
    and "base.opacity(edge == .top" in CHAT
    and "ChatFrostedEdgeMask(edge: .top, base: chatTopMaskBase)" in CHAT
    and "ChatFrostedEdgeMask(edge: .bottom, base: chatBottomMaskBase)" in CHAT
    and "ChatTopGlassBackdrop" not in CHAT
    and "ChatImmersiveEdgeMask" not in CHAT
    and "ChatMaterialGrainOverlay()" not in CHAT,
    "chat top and bottom must share one subtle native-frosted page-colour falloff",
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
    and "ChatFrostedEdgeMask(edge: .top, base: chatTopMaskBase)" in CHAT
    and "ChatFrostedEdgeMask(edge: .bottom, base: chatBottomMaskBase)" in CHAT,
    "header controls may keep their adaptive surface while masks stay lightly frosted",
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
    and "Color(hex: 0x111111)" in CHAT
    and "composerUtilityInk.opacity(0.82)" in CHAT,
    "composer utility icons and placeholder must retain readable contrast",
)
require(
    "python3 tools/verify-chat-chrome-contrast.py" in WORKFLOW,
    "chat chrome contrast regression must run in the iOS gate",
)

print("chat-chrome-contrast: passed")
