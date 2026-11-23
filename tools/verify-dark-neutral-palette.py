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
    ("pageBg", "0xFFFFFF", "0x0E0F12"),
    ("navBg", "0xFFFFFF", "0x15161A"),
    ("tabBg", "0xFFFFFF", "0x121317"),
    ("chatRowBg", "0xFFFFFF", "0x121317"),
    ("chatsTopBg", "0xFFFFFF", "0x15161A"),
    ("chatsPageBg", "0xFFFFFF", "0x0E0F12"),
    ("chatsRowBg", "0xFFFFFF", "0x121317"),
    ("contactsBg", "0xFFFFFF", "0x0E0F12"),
    ("discoverBg", "0xEDEDED", "0x0E0F12"),
):
    require(
        f'UIConfig.fixedDark("{key}", {light}, {dark})' in CORE,
        f"{key} must use its explicit dark elevation level",
    )
require(
    "background ?? (isDark ? C.pageBg" in NAV,
    "the dark native chrome fallback must use the app-wide canvas",
)
require(
    "let fill = scheme == .dark\n            ? C.tabBg" in MAIN_TAB
    and "let themed = scheme == .dark\n                ? C.pageBg" in TAB
    and "let themed = C.pageBg" in TAB,
    "dark navigation and tab surfaces must ignore legacy remote black overrides",
)

print("dark-neutral-palette: passed")
