#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat edge mask verification failed: " + message)


require(
    "private struct NativeChatFrostedEdgeMaterial" in CHAT
    and "let edge: ChatWallpaperEdge" in CHAT
    and ".systemUltraThinMaterialDark" in CHAT
    and ".systemThinMaterialDark" in CHAT
    and ".systemThinMaterialLight" in CHAT
    and "NativeChatFrostedEdgeMaterial(edge: edge)" in CHAT
    and "private struct ChatFrostedEdgeMask" in CHAT
    and "let edge: ChatWallpaperEdge" in CHAT
    and "let base: Color" in CHAT
    and "if reduceTransparency || !performance.allowsBackdropBlur {\n                    base" in CHAT
    and "base.opacity(edge == .top" in CHAT
    and "(scheme == .dark ? 0.78 : 0.86)" in CHAT
    and "(scheme == .dark ? 0.72 : 0.82)" in CHAT,
    "both edges must use restrained native material rather than a solid cover",
)
require(
    "private var chatTopMaskBase: Color" in CHAT
    and "private var chatBottomMaskBase: Color" in CHAT
    and "if usesPlainDefaultChatChrome { return ChatTheme.page }" in CHAT
    and "topBarUsesLightInk ? Color.black : Color.white" in CHAT
    and "composerUsesLightInk ? Color.black : Color.white" in CHAT,
    "mask tint must follow the chat background theme and sampled wallpaper luminance",
)
require(
    CHAT.count("ChatFrostedEdgeMask(edge: .top, base: chatTopMaskBase)") == 1
    and CHAT.count("ChatFrostedEdgeMask(edge: .bottom, base: chatBottomMaskBase)") == 1
    and ".frame(height: 0.5)" in CHAT
    and "Color.white.opacity(0.055)" in CHAT
    and "Color.black.opacity(0.065)" in CHAT,
    "top and composer surfaces must use matching solid edges and one hairline",
)
require(
    "python3 tools/verify-chat-edge-masks.py" in WORKFLOW,
    "chat edge mask regression must run in the iOS gate",
)

print("chat-edge-masks: passed")
