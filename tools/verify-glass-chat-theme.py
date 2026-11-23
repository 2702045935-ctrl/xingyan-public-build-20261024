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


def relative_luminance(hex_color: str) -> float:
    channels = [
        int(hex_color[index:index + 2], 16) / 255
        for index in (0, 2, 4)
    ]
    linear = [
        value / 12.92
        if value <= 0.04045
        else ((value + 0.055) / 1.055) ** 2.4
        for value in channels
    ]
    return (
        0.2126 * linear[0]
        + 0.7152 * linear[1]
        + 0.0722 * linear[2]
    )


def contrast(foreground: str, background: str) -> float:
    values = sorted(
        [relative_luminance(foreground), relative_luminance(background)],
        reverse=True,
    )
    return (values[0] + 0.05) / (values[1] + 0.05)


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
    and "cornerRadius: WhatsAppChatLayout.bubbleRadius" in TEXT_ROW
    and "context.drawLinearGradient(" in TEXT_ROW
    and "ChatSurfaceMaterial.uiBubble(" in TEXT_ROW
    and "UIColor.white.withAlphaComponent(mine" in SURFACE
    and "path.lineWidth = 0.8" in TEXT_ROW
    and "bubble.glass = next.bubbleGlass" in MEDIA_ROW,
    "UIKit text and media bubbles must pre-render glass highlights on WhatsApp paths",
)
require(
    "static let mention = Color.dyn(0x007A63, 0x82D9C7)" in CHAT
    and "static let code = Color.dyn(0x5A3A7D, 0xD2B2FF)" in CHAT
    and "static let link = Color.dyn(0x0A5FC2, 0x8FC7FF)" in CHAT
    and "Color.dyn(0x8F261C, 0x5D1A14)" in CHAT
    and "seg.foregroundColor = bubbleCodeInk" in CHAT
    and "seg.foregroundColor = bubbleMentionMeInk" in CHAT
    and "seg.foregroundColor = bubbleMentionInk" in CHAT
    and "ChatTheme.preset.rawValue," in CHAT
    and "senderNameUsesLightInk ? \"light-ink\" : \"adaptive-ink\"" in CHAT
    and "mineNames.joined(separator: \",\")" in CHAT,
    "special text must use semantic mention, self-mention and code colors with theme-aware caching",
)
for foreground, background in [
    ("007A63", "FFFFFF"),
    ("82D9C7", "2C2C2E"),
    ("B42318", "FFFFFF"),
    ("FF9E91", "2C2C2E"),
    ("0A5FC2", "FFFFFF"),
    ("8FC7FF", "2C2C2E"),
    ("5A3A7D", "FFFFFF"),
    ("D2B2FF", "2C2C2E"),
    ("075E54", "95EC69"),
    ("0B3D32", "3EB575"),
    ("8F261C", "95EC69"),
    ("5D1A14", "3EB575"),
    ("0A4C96", "95EC69"),
    ("0A2F57", "3EB575"),
    ("4F2A75", "95EC69"),
    ("3C2457", "3EB575"),
    ("111111", "95EC69"),
    ("4C5B50", "95EC69"),
    ("0B1A12", "3EB575"),
    ("1D3429", "3EB575"),
]:
    require(
        contrast(foreground, background) >= 4.5,
        f"special text {foreground} on {background} must meet 4.5:1 contrast",
    )
require(
    "if raw.split(separator: \"\\n\", omittingEmptySubsequences: false)" in CHAT
    and ".contains(where: { RichText.looksLikeCode(String($0)) })" in CHAT,
    "code-like messages must use the themed rich-text renderer",
)
require(
    "python3 tools/verify-glass-chat-theme.py" in WORKFLOW,
    "glass chat theme regression must run in the iOS gate",
)

print("glass-chat-theme: passed")
