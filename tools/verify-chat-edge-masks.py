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
    and ".systemThinMaterialDark" in CHAT
    and ".systemThinMaterialLight" in CHAT
    and "private struct ChatFrostedEdgeMask" in CHAT
    and "let edge: ChatWallpaperEdge" in CHAT
    and "let base: Color" in CHAT
    and "if reduceTransparency {\n                    base" in CHAT,
    "both chat edges must use the shared system thin material with an opaque accessibility fallback",
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
    and "edge == .top\n                    ? [" in CHAT
    and ".init(color: base.opacity(0.90), location: 0)" in CHAT
    and ".init(color: base.opacity(0.94), location: 1)" in CHAT,
    "top and bottom masks must use separate falloff curves for header and composer surfaces",
)
require(
    "python3 tools/verify-chat-edge-masks.py" in WORKFLOW,
    "chat edge mask regression must run in the iOS gate",
)

print("chat-edge-masks: passed")
