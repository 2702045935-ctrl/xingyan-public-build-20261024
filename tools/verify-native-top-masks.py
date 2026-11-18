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
        and "NativeGlassHeaderMaterial()" in NAV
        and "accessibilityReduceTransparency" in NAV,
        "shared top mask must use the iOS native glass with accessibility fallback")
require(".glassEffect(.regular.interactive(), in: shape)" in NAV,
        "tappable glass controls must use native interactive liquid glass")
require(
    "collection.topEdgeEffect.style = .hard" in NATIVE_LIST
    and "collection.topEdgeEffect.isHidden = false" in NATIVE_LIST
    and "NativeChatListScrollRegistry.shared.chats = collection" in NATIVE_LIST,
    "chat list must expose the system scroll-edge effect instead of a custom glass strip",
)
require(
    "UIScrollEdgeElementContainerInteraction" in NAV
    and "interaction.edge = .top" in NAV
    and "let edgeShape = UIView()" in NAV
    and "NativeChatsTopEdgeChrome(scrolled: scrolled)" in CHATS
    and "NativeTopGlassMask(active: scrolled > 0)" not in CHATS,
    "chat header must extend the native scroll edge through its full height",
)
require("NativeTopGlassMask(active: navScrolled > 0)" in CONTACTS
        and "TopGlassBar(" not in CONTACTS
        and "TopGlassLine(" not in CONTACTS,
        "contacts must remove its custom top material")
require("NativeTopGlassMask(active: navScrolled > 0)" in DISCOVER
        and "TopGlassBar(" not in DISCOVER
        and "TopGlassLine(" not in DISCOVER,
        "world top bar must use the shared native material")

print("native-top-masks: passed")
