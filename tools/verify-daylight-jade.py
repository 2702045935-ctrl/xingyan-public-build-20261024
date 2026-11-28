#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORE = (ROOT / "Sources" / "Core.swift").read_text(encoding="utf-8")
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
ROW = (ROOT / "Sources" / "NativeChatRowCell.swift").read_text(encoding="utf-8")
NAV = (ROOT / "Sources" / "NavGlass.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
TAB = (ROOT / "Sources" / "NativeTabBar.swift").read_text(encoding="utf-8")
CONTACTS = (ROOT / "Sources" / "ContactsView.swift").read_text(encoding="utf-8")
PROFILE = (ROOT / "Sources" / "Profile.swift").read_text(encoding="utf-8")
MISC = (ROOT / "Sources" / "MiscPages.swift").read_text(encoding="utf-8")
SEARCH = (ROOT / "Sources" / "SearchPage.swift").read_text(encoding="utf-8")
MALL = (ROOT / "Sources" / "MallNative.swift").read_text(encoding="utf-8")
SHARE = (ROOT / "Sources" / "ShareSheet.swift").read_text(encoding="utf-8")
SIDEBAR = (ROOT / "Sources" / "AccountSidebarView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("daylight-jade verification failed: " + message)


for token in (
    'UIConfig.fixedDark("pageBg", 0xF2F4F1, 0x000000)',
    'UIConfig.fixedDark("cardBg", 0xFAFBF9, 0x1C1C1E)',
    'UIConfig.fixedDark("chatsRowBg", 0xFAFBF9, 0x000000)',
    'UIConfig.fixedDark("previewColor", 0x626B66, 0xAEAEB2)',
    'UIConfig.fixedDark("timeColor", 0x858D88, 0x8E8E93)',
    'UIConfig.fixedDark("lineColor", 0xDDE2DD, 0x38383A)',
):
    require(token in CORE, "missing shared Apple Messages dark token: " + token)

require(
    "chatsIsDark\n            ? C.pageBg" in CHATS
    and "chatsIsDark\n            ? Color(hex: 0x2A2A2C)" in CHATS
    and "chatsIsDark\n            ? C.chatRowBg" in CHATS
    and "UIColor(hex: isDark ? 0x8D8D93 : 0x626B66)" in CHATS
    and "UIColor(hex: isDark ? 0x74767A : 0x858D88)" in CHATS,
    "conversation surfaces must share the softened Apple Messages dark hierarchy",
)
require(
    "weight: .semibold, textStyle: .headline" in ROW
    and "titleRow.transform = CGAffineTransform(translationX: 0, y: -1)" in ROW,
    "conversation title must use the calibrated semibold optical rhythm",
)
require(
    "glassEffect(" not in NAV
    and NAV.count("UIBlurEffect(") == 3
    and NAV.count("UIGlassEffect(") == 1
    and "NativeMediaGlassSurface(shape: shape, interactive: interactive)" in NAV,
    "custom glass must be removed while native masks and media glass remain",
)
require(
    "NativeGlassHeaderMaterial(forcedDark: lightInk)" in CHAT
    and "Color.white.opacity(effectiveDark ? 0.055 : 0.13)" not in CHAT
    and "Color.black.opacity(effectiveDark ? 0.10 : 0.018)" not in CHAT,
    "chat masks must not restore a mirror highlight",
)
require(
    "Color.dyn(0x757D78, 0x8E8E93)" in TAB
    and "Color.dyn(0x117A58, 0x42C693)" in TAB,
    "tab icons must share the neutral Apple hierarchy and jade accent",
)
require(
    'UIConfig.colorIfSet("contactsBg") ?? C.contactsBg' in CONTACTS
    and "private var sheetBg: Color { C.cardBg }" in CONTACTS
    and "private var pageChrome: Color { C.pageBg }" in PROFILE
    and ".background(C.pageBg)" in MISC
    and "private var xhsCanvas: Color {\n        C.pageBg" in SEARCH
    and "static let page     = C.pageBg" in MALL
    and "static let card     = C.cardBg" in MALL
    and "static func page(_ scheme: ColorScheme) -> Color {\n        C.pageBg"
    in SHARE,
    "contacts, settings, world, search, mall and share must share the same surface system",
)
require(
    "NativeGlassHeaderMaterial(forcedDark: scheme == .dark)" in SIDEBAR
    and "Color.white.opacity(scheme == .dark ? 0.08 : 0.22)" not in SIDEBAR,
    "sidebar must use the shared opaque surface without top specular light",
)
require(
    "Color.clear\n                        .frame(height: L.safeTop + chatsHeaderH + chatsSearchH)"
    in CHATS
    and "id: \"search\",\n                kind: .search" in CHATS
    and "chatsSearchBar\n                    if chatFilterVisible" not in CHATS
    and "chatTopHeader\n                        .background" in CHATS,
    "search must stay in the list so it enters the mask only while scrolling",
)
require(
    "python3 tools/verify-daylight-jade.py" in WORKFLOW,
    "the visual system regression must run in the iOS gate",
)

print("daylight-jade: passed")
