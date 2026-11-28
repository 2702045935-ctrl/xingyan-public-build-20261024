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
        and "if !active {\n                Color.clear" in NAV
        and "if !reduceTransparency {\n                        NativeFrostedHeaderMaterial(chrome: edgeBlend)" in NAV
        and "UIScrollEdgeElementContainerInteraction" in NAV
        and "table.topEdgeEffect.style = .automatic" in NATIVE_LIST
        and ".systemChromeMaterialDark" in NAV
        and NAV.count("UIGlassEffect(") == 1
        and "glassEffect(" not in NAV,
        "shared top mask must use native materials while media controls keep one system glass component")
require("NativeGlassControlMaterial" in NAV
        and "NativeMediaGlassSurface(shape: shape, interactive: interactive)" in NAV
        and "shape\n            .fill(C.floatingSurface)" not in NAV,
        "controls must use the single native system glass source")
require(
    "var base: Color = C.pageBg" in NAV
    and "base.opacity(reduceTransparency ? 1 : 0.90)" in NAV,
    "scroll masks must tint to the exact page background before blur",
)
require(
    "table.topEdgeEffect.style = .automatic" in NATIVE_LIST
    and "table.topEdgeEffect.isHidden = true" in NATIVE_LIST
    and "scrollView.topEdgeEffect.isHidden = hidden" in NATIVE_LIST
    and "NativeChatListScrollRegistry.shared.chats = table" in NATIVE_LIST,
    "chat list must expose the native scroll-edge effect only after leaving rest",
)
require(
    "UIScrollEdgeElementContainerInteraction" in NAV
    and "interaction.edge = .top" in NAV
    and "let edgeShape = UIView()" in NAV
    and "if #available(iOS 26.0, *), !isDark" not in NAV
    and ".ignoresSafeArea(edges: .top)" in NAV
    and "NativeTopGlassMask(active: chatTopScrolled > 0," in CHATS
    and "edgeBlend: true" in CHATS
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
    and "NativeTopGlassMask(active: chatTopScrolled > 0," in CHATS
    and "edgeBlend: true" in CHATS
    and "NativeChatListScrollRegistry.shared.chats" in CHATS
    and "chatTopHeader\n                        .background" in CHATS,
    "resting search must stay at the legacy position while the mask activates only after scrolling",
)
require("NativeTopGlassMask(active: navScrolled > 0," in CONTACTS
        and "base: contactsCanvas" in CONTACTS
        and "NativeTopScrollObserver" in CONTACTS
        and "NativeScrollEdgeElementBridge(" in CONTACTS
        and "NativeTopScrollRegistry.shared.contacts = scroll" in CONTACTS
        and "onScrollViewReady:" in NAV
        and "topScrollTracking($navScrolled" not in CONTACTS
        and "TopGlassBar(" not in CONTACTS
        and "TopGlassLine(" not in CONTACTS,
        "contacts must observe the native scroll view and remove its custom top material")
require("NativeTopGlassMask(active: navScrolled > 0," in DISCOVER
        and "base: worldCanvas" in DISCOVER
        and "NativeTopScrollObserver" in DISCOVER
        and "topScrollTracking($navScrolled" not in DISCOVER
        and "TopGlassBar(" not in DISCOVER
        and "TopGlassLine(" not in DISCOVER,
        "world top bar must observe the native scroll view and use the shared material")
require(
    "struct NativeChatFrostedEdgeMaterial" in CHAT
    and ".systemThinMaterialDark" in CHAT
    and "struct ChatFrostedEdgeMask" in CHAT
    and "ChatFrostedEdgeMask(edge: .top, base: chatTopMaskBase)" in CHAT
    and "ChatFrostedEdgeMask(edge: .bottom, base: chatBottomMaskBase)" in CHAT
    and "ChatImmersiveEdgeMask" not in CHAT
    and "ChatTopGlassBackdrop" not in CHAT,
    "chat chrome must use the same lightly frosted background-matched masks in both themes",
)

print("native-top-masks: passed")
