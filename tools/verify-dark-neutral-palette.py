#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ROW = (ROOT / "Sources" / "NativeChatRowCell.swift").read_text(encoding="utf-8")
TAB = (ROOT / "Sources" / "NativeTabBar.swift").read_text(encoding="utf-8")
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
CORE = (ROOT / "Sources" / "Core.swift").read_text(encoding="utf-8")
NAV = (ROOT / "Sources" / "NavGlass.swift").read_text(encoding="utf-8")
MAIN_TAB = (ROOT / "Sources" / "MainTab.swift").read_text(encoding="utf-8")
CONTACTS = (ROOT / "Sources" / "ContactsView.swift").read_text(encoding="utf-8")
DISCOVER = (ROOT / "Sources" / "DiscoverView.swift").read_text(encoding="utf-8")


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
require(
    "chatsIsDark\n            ? Color(hex: 0x0D0F11)\n            : C.pageBg" in CHATS
    and "scheme == .dark ? C.contactsBg\n            : C.pageBg" in CONTACTS
    and "scheme == .dark ? C.discoverBg\n            : C.pageBg" in DISCOVER,
    "light primary pages must inherit the configured page canvas",
)
require(
    "chatsIsDark\n            ? Color(hex: 0x15181B)\n            : Color.white" in CHATS
    and "Color(hex: 0xE2E4E6)" in CHATS,
    "the light search field must stay distinct from the page canvas",
)
for key, light, dark in (
    ("pageBg", "0xFFFFFF", "0x0D0F11"),
    ("navBg", "0xFFFFFF", "0x0D0F11"),
    ("tabBg", "0xFFFFFF", "0x0D0F11"),
    ("chatRowBg", "0xFFFFFF", "0x0D0F11"),
    ("chatsTopBg", "0xFFFFFF", "0x0D0F11"),
    ("chatsPageBg", "0xFFFFFF", "0x0D0F11"),
    ("chatsRowBg", "0xFFFFFF", "0x0D0F11"),
    ("contactsBg", "0xFFFFFF", "0x0D0F11"),
    ("discoverBg", "0xEDEDED", "0x0D0F11"),
):
    require(
        f'UIConfig.fixedDark("{key}", {light}, {dark})' in CORE,
        f"{key} must share the graphite dark canvas",
    )
require(
    "NativeGraphiteChromeTexture" not in NAV
    and "background ?? (isDark ? C.pageBg" in NAV
    and ".opacity(scrolled > 0 ? 1 : 0)" in NAV,
    "native chrome must restore the b2611270050 themed edge surface",
)
require(
    "let fill = scheme == .dark\n            ? C.tabBg" in MAIN_TAB
    and "appearance.configureWithDefaultBackground()" in TAB
    and "UIBlurEffect(style: .systemChromeMaterial)" in TAB
    and "systemUltraThinMaterialDark" not in TAB
    and "TabGlassBackdrop" not in TAB,
    "tab surfaces must restore b2611270050 native system chrome",
)
require(
    "private enum NativeTabBarVisual" in TAB
    and "static var normalInk: Color { Color.dyn(0x6E6E73, 0x8E8E93) }" in TAB
    and "static var selectedInk: Color { Color.dyn(0x0F8B65, 0x36CA95) }" in TAB
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
