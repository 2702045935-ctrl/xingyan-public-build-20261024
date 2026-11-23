#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
THEMES = (ROOT / "Sources" / "ChatThemes.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
WALLPAPER = (ROOT / "Sources" / "ChatWallpaperEffect.swift").read_text(encoding="utf-8")
TEXT_ROW = (ROOT / "Sources" / "NativeChatTextRowCell.swift").read_text(encoding="utf-8")
SURFACE = (ROOT / "Sources" / "ChatSurfaceMaterial.swift").read_text(encoding="utf-8")
MEDIA_ROW = (ROOT / "Sources" / "NativeChatMediaRowCell.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("glass chat theme verification failed: " + message)


require(
    "case glass" in THEMES
    and 'case .glass: return Tr("玻璃")' in THEMES
    and 'case .glass: return Color.dyn(0x2F8F78, 0x0B6B58)' in THEMES
    and 'case .glass: return Color.dyn(0xF7FBF9, 0x1A2421)' in THEMES
    and "currentPreset: ChatAppearancePreset = .glass" in THEMES
    and "ChatAppearancePreset(rawValue: raw) ?? .glass" in THEMES,
    "glass must be the first-use chat appearance with distinct send/receive colors",
)
require(
    "static var usesGlass: Bool { preset == .glass }" in CHAT
    and "if activeGlass" in CHAT
    and "ChatSurfaceMaterial.bubble(" in CHAT
    and "dark ? 0.17 : 0.42" in SURFACE
    and "let r = min(pill ? min(rect.height / 2, 24) : radius" in CHAT,
    "glass bubbles must use the unified WhatsApp geometry and restrained highlights",
)
require(
    "case .glass:\n            glassScene(size: size)" in WALLPAPER
    and "private func glassScene(size: CGSize)" in WALLPAPER
    and "Color(hex: 0x2F8F78).opacity(dark ? 0.22 : 0.18)" in WALLPAPER
    and "Canvas { context, canvas in" in WALLPAPER,
    "glass must have a static atmospheric backdrop without animated blur",
)
require(
    "var bubbleGlass: Bool" in TEXT_ROW
    and "var glass = false" in TEXT_ROW
    and "cornerRadius: 8" in TEXT_ROW
    and "context.drawLinearGradient(" in TEXT_ROW
    and "ChatSurfaceMaterial.uiBubble(" in TEXT_ROW
    and "UIColor.white.withAlphaComponent(mine" in SURFACE
    and "path.lineWidth = 0.8" in TEXT_ROW
    and "bubble.glass = next.bubbleGlass" in MEDIA_ROW,
    "UIKit text and media bubbles must pre-render glass highlights on WhatsApp paths",
)
require(
    "python3 tools/verify-glass-chat-theme.py" in WORKFLOW,
    "glass chat theme regression must run in the iOS gate",
)

print("glass-chat-theme: passed")
