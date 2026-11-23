#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
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
    "private struct ChatCleanEdgeMask" in CHAT
    and "scheme == .light && !topBarUsesLightInk" in CHAT
    and "scheme == .light && !composerUsesLightInk" in CHAT
    and "ChatCleanEdgeMask(" in CHAT,
    "light chat chrome must use a clean edge surface instead of layered wallpaper effects",
)
require(
    "if composerUsesLightInk" in CHAT
    and "NativeGlassHeaderMaterial(forcedDark: true)" in CHAT
    and "Color(uiColor: .systemBackground).opacity(0.97)" in CHAT,
    "composer field backing must be solid in light mode and keep glass over dark wallpapers",
)
require(
    "NativeGlassHeaderMaterial(forcedDark: lightInk)" in CHAT
    and "capsule.fill(lightInk" in CHAT
    and "ChatTopGlassBackdrop(lightInk: topBarUsesLightInk)" in CHAT,
    "top header glass and icon capsules must switch to dark material over black wallpapers",
)
require(
    CHAT.count("if !path.isEmpty { return true }") >= 2,
    "unsampled custom wallpapers must default to light chrome instead of system light ink",
)
require(
    "NativeGlassHeaderMaterial(forcedDark:" in CHAT
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
require(
    CHATS.count("NativeChatsTopEdgeChrome(") >= 2
    and "Cover the complete scrolling chrome region" in CHATS
    and "background: chatsPageFill" in CHATS,
    "the full chat-list chrome must mask scrolling rows instead of exposing clipped half-rows",
)

print("chat-chrome-contrast: passed")
