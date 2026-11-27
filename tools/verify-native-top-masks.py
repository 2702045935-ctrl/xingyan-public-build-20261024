#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
CONTACTS = (ROOT / "Sources" / "ContactsView.swift").read_text(encoding="utf-8")
DISCOVER = (ROOT / "Sources" / "DiscoverView.swift").read_text(encoding="utf-8")
NAV = (ROOT / "Sources" / "NavGlass.swift").read_text(encoding="utf-8")
NATIVE_LIST = (ROOT / "Sources" / "NativeChatList.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("native top mask verification failed: " + message)


require("struct NativeTopGlassMask" in NAV
        and "struct NativeFrostedHeaderMaterial" in NAV
        and "UIBlurEffect(style: scheme == .dark" in NAV
        and "if !active {\n                Color.clear" in NAV
        and "} else {\n                NativeFrostedHeaderMaterial()" in NAV
        and "UIScrollEdgeElementContainerInteraction" in NAV
        and "table.topEdgeEffect.style = .automatic" in NATIVE_LIST
        and "NativeFrostedHeaderMaterial()" in NAV
        and "UIGlassEffect" not in NAV
        and "glassEffect(" not in NAV,
        "shared top mask must use only the native system material")
require("shape\n            .fill(C.floatingSurface)" in NAV
        and "shape.stroke(C.hairline" in NAV,
        "controls must use an opaque floating surface")
require(
    "table.topEdgeEffect.style = .automatic" in NATIVE_LIST
    and "table.topEdgeEffect.isHidden = false" in NATIVE_LIST
    and "NativeChatListScrollRegistry.shared.chats = table" in NATIVE_LIST,
    "chat list must expose the native scroll-edge effect",
)
require(
    "UIScrollEdgeElementContainerInteraction" in NAV
    and "interaction.edge = .top" in NAV
    and "let edgeShape = UIView()" in NAV
    and "if #available(iOS 26.0, *), !isDark" not in NAV
    and ".ignoresSafeArea(edges: .top)" in NAV
    and "NativeTopGlassMask(active: chatTopScrolled > 0)" in CHATS
    and "NativeChatListScrollRegistry.shared.chats" in CHATS
    and "onOffsetChange:" in CHATS
    and "NativeTopGlassMask(active: scrolled > 0)" not in CHATS,
    "chat header must bind to the native scroll edge with an opaque safety layer",
)
require(
    "NativeChatsTopEdgeChrome" not in NAV
    and "struct NativeTopGlassMask" in NAV
    and "struct NativeFrostedHeaderMaterial" in NAV,
    "the old custom conversation mask must be removed",
)
require(
    "Color.clear\n                        .frame(height: L.safeTop + chatsHeaderH + chatsSearchH)"
    in CHATS
    and "id: \"search\",\n                kind: .search" in CHATS
    and ".frame(height: chatsSearchH)\n        .offset(y: -6)" in CHATS
    and "NativeTopGlassMask(active: chatTopScrolled > 0)" in CHATS
    and "NativeChatListScrollRegistry.shared.chats" in CHATS
    and "chatTopHeader\n                        .background" in CHATS,
    "resting search must stay at the legacy position while the mask activates only after scrolling",
)
require("NativeTopGlassMask(active: navScrolled > 0)" in CONTACTS
        and "NativeTopScrollObserver" in CONTACTS
        and "NativeScrollEdgeElementBridge(" in CONTACTS
        and "NativeTopScrollRegistry.shared.contacts = scroll" in CONTACTS
        and "onScrollViewReady:" in NAV
        and "topScrollTracking($navScrolled" not in CONTACTS
        and "TopGlassBar(" not in CONTACTS
        and "TopGlassLine(" not in CONTACTS,
        "contacts must observe the native scroll view and remove its custom top material")
require("NativeTopGlassMask(active: navScrolled > 0)" in DISCOVER
        and "NativeTopScrollObserver" in DISCOVER
        and "topScrollTracking($navScrolled" not in DISCOVER
        and "TopGlassBar(" not in DISCOVER
        and "TopGlassLine(" not in DISCOVER,
        "world top bar must observe the native scroll view and use the shared material")

print("native-top-masks: passed")
