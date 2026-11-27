#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ROW = (ROOT / "Sources" / "NativeChatRowCell.swift").read_text(encoding="utf-8")
TAB = (ROOT / "Sources" / "NativeTabBar.swift").read_text(encoding="utf-8")
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
CORE = (ROOT / "Sources" / "Core.swift").read_text(encoding="utf-8")
NAV = (ROOT / "Sources" / "NavGlass.swift").read_text(encoding="utf-8")
MAIN_TAB = (ROOT / "Sources" / "MainTab.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("dark neutral palette verification failed: " + message)


require(ROW.count("private static func previewTokenColor") == 1
        and ROW.count("private static func previewKindColor") == 1
        and "previewTokenColor(token," in ROW
        and "previewKindColor(kind," in ROW,
        "message-type preview tokens must stay neutral in both light and dark chat lists")
require("unreadLabel.backgroundColor = .systemRed" in ROW
        and "systemBlue" not in CHATS,
        "unread counts must use the single red badge language")
for key, light, dark in (
    ("pageBg", "0xF2F4F1", "0x101412"),
    ("navBg", "0xF5F6F4", "0x101412"),
    ("tabBg", "0xF5F6F4", "0x121613"),
    ("chatRowBg", "0xFAFBF9", "0x171B18"),
    ("chatsTopBg", "0xF4F6F3", "0x101412"),
    ("chatsPageBg", "0xF2F4F1", "0x101412"),
    ("chatsRowBg", "0xFAFBF9", "0x171B18"),
    ("contactsBg", "0xF2F4F1", "0x101412"),
    ("discoverBg", "0xF2F4F1", "0x101412"),
):
    require(
        f'UIConfig.fixedDark("{key}", {light}, {dark})' in CORE,
        f"{key} must use the daylight-jade surface ladder",
    )
require(
    "background ?? (isDark ? C.pageBg" in NAV,
    "the dark native chrome fallback must use the app-wide canvas",
)
require(
    "let fill = scheme == .dark\n            ? C.tabBg" in MAIN_TAB
    and "appearance.configureWithDefaultBackground()" in TAB
    and "UIBlurEffect(style: .systemChromeMaterial)" in TAB
    and "systemUltraThinMaterialDark" not in TAB
    and "TabGlassBackdrop" not in TAB,
    "tab surfaces must use native system chrome instead of stacked custom blur",
)
require(
    "private enum NativeTabBarVisual" in TAB
    and "static var normalInk: Color { Color.dyn(0x757D78, 0x8B938E) }" in TAB
    and "static var selectedInk: Color { Color.dyn(0x117A58, 0x42C693) }" in TAB
    and "let normalIcon = UIColor(NativeTabBarVisual.normalInk)" in TAB
    and "let selectedIcon = UIColor(NativeTabBarVisual.selectedInk)" in TAB
    and "appearance.inlineLayoutAppearance" in TAB
    and "appearance.compactInlineLayoutAppearance" in TAB
    and ".withRenderingMode(.alwaysTemplate)" in TAB
    and "messageIconWithEyes" not in TAB
    and "worldIconWithOrbit" not in TAB
    and "circularAvatar(avatar, selected: selected)" in TAB
    and "ring.lineWidth = 1.5" in TAB,
    "tab icons must share one template tint hierarchy in every layout",
)

print("dark-neutral-palette: passed")
