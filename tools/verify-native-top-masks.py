#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
CONTACTS = (ROOT / "Sources" / "ContactsView.swift").read_text(encoding="utf-8")
DISCOVER = (ROOT / "Sources" / "DiscoverView.swift").read_text(encoding="utf-8")
NAV = (ROOT / "Sources" / "NavGlass.swift").read_text(encoding="utf-8")
NATIVE_LIST = (ROOT / "Sources" / "NativeChatList.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("native top mask verification failed: " + message)


require("struct NativeTopGlassMask" in NAV
        and "struct NativeFrostedHeaderMaterial" in NAV
        and "UIBlurEffect(style: scheme == .dark" in NAV
        and "NativeFrostedHeaderMaterial()" in NAV
        and "accessibilityReduceTransparency" in NAV,
        "shared top mask must use a visible native frosted material with accessibility fallback")
require(".glassEffect(.regular.interactive(), in: shape)" in NAV,
        "tappable glass controls must use native interactive liquid glass")
require(
    "table.topEdgeEffect.style = .hard" in NATIVE_LIST
    and "table.topEdgeEffect.isHidden = true" in NATIVE_LIST
    and "NativeChatListScrollRegistry.shared.chats = table" in NATIVE_LIST,
    "chat list must keep the system scroll-edge line hidden to prevent a first-frame flash",
)
require(
    "NativeScrollEdgeElementBridge(" in CONTACTS
    and "NativeScrollEdgeElementBridge(" in DISCOVER
    and ".ignoresSafeArea(edges: .top)" in NAV
    and "NativeChatsTopEdgeChrome(scrolled: chatTopScrolled," in CHATS
    and "dark: chatsIsDark" in CHATS
    and "background: chatsPageFill" in CHATS
    and "onOffsetChange:" in CHATS
    and "NativeTopGlassMask(active: scrolled > 0)" not in CHATS,
    "chat header must restore the b2611270050 themed edge surface",
)
require(
    "NativeChatsTopEdgeChrome" in NAV
    and "NativeGraphiteChromeTexture" not in NAV
    and "private var isDark" in NAV
    and "(background ?? (isDark ? C.pageBg : Color(uiColor: .systemBackground)))" in NAV
    and ".opacity(scrolled > 0 ? 1 : 0)" in NAV,
    "chat chrome must restore the b2611270050 edge implementation",
)
require("NativeTopGlassMask(active: navScrolled > 0)" in CONTACTS
        and "NativeTopScrollObserver" in CONTACTS
        and "NativeTopScrollRegistry.shared.contacts = scroll" in CONTACTS
        and "onScrollViewReady:" in NAV
        and "topScrollTracking($navScrolled" not in CONTACTS
        and "TopGlassBar(" not in CONTACTS
        and "TopGlassLine(" not in CONTACTS,
        "contacts must observe the native scroll view and remove its custom top material")
require("NativeTopGlassMask(active: navScrolled > 0)" in DISCOVER
        and "NativeTopScrollObserver" in DISCOVER
        and "NativeScrollEdgeElementBridge(" in DISCOVER
        and "topScrollTracking($navScrolled" not in DISCOVER
        and "TopGlassBar(" not in DISCOVER
        and "TopGlassLine(" not in DISCOVER,
        "world top bar must observe the native scroll view and restore the b2611270050 edge bridge")

require(
    "ChatTopGlassBackdrop(lightInk: topBarUsesLightInk)" in CHAT
    and "ChatBottomGlassBackdrop" not in CHAT
    and "ChatImmersiveEdgeMask(path:" in CHAT
    and "else if scheme == .light" in CHAT,
    "chat top and composer edges must restore the b2611270050 wallpaper-aware masks",
)

print("native-top-masks: passed")
