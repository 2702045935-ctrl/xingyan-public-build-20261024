#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAIN = (ROOT / "Sources" / "MainTab.swift").read_text(encoding="utf-8")
SWIPE = (ROOT / "Sources" / "SwipeBack.swift").read_text(encoding="utf-8")
SEARCH = (ROOT / "Sources" / "SearchPage.swift").read_text(encoding="utf-8")
CONTACTS = (ROOT / "Sources" / "ContactsView.swift").read_text(encoding="utf-8")
SIDEBAR = (ROOT / "Sources" / "AccountSidebarView.swift").read_text(encoding="utf-8")
DISCOVER = (ROOT / "Sources" / "DiscoverView.swift").read_text(encoding="utf-8")
NATIVE_CHAT_LIST = (ROOT / "Sources" / "NativeChatList.swift").read_text(encoding="utf-8")
CHAT_DETAIL = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
NAV_GLASS = (ROOT / "Sources" / "NavGlass.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("handfeel verification failed: " + message)


require(
    "transaction.disablesAnimations = true" in MAIN
    and "withTransaction(transaction)" in MAIN,
    "tab selection must publish without an implicit page animation",
)
require(
    "SystemNavBackPressStyle" in MAIN
    and ".interactiveSpring(response: 0.20, dampingFraction: 0.86)" in MAIN
    and "UISelectionFeedbackGenerator().selectionChanged()" in MAIN,
    "navigation back must provide immediate press and selection feedback",
)
require(
    "opacity(configuration.isPressed ? 0.045 : 0)" in MAIN
    and ".scaleEffect(configuration.isPressed ? 0.992 : 1)" in MAIN
    and ".easeOut(duration: 0.08)" in MAIN,
    "shared menu rows must use restrained, immediate press feedback",
)
require(
    "response: 0.24, dampingFraction: 0.92" in SWIPE
    and "deadline: .now() + 0.14" in SWIPE
    and "impactOccurred(intensity: 0.65)" in SWIPE,
    "interactive back must settle within 140ms with one light confirmation",
)
require(
    "deadline: .now() + 0.22" in SEARCH
    and "deadline: .now() + 0.12" in CONTACTS
    and "deadline: .now() + 0.12" in SIDEBAR,
    "keyboard, contacts and sidebar transitions must avoid visible waits",
)
require(
    'case "map": StarWorldExperienceView()' in DISCOVER
    and 'case "map": StarMapView()' not in DISCOVER,
    "the world entry must open the new experience without the legacy page",
)
require(
    "if table.refreshControl == nil" in NATIVE_CHAT_LIST
    and "private func revealInitialTableIfNeeded" in NATIVE_CHAT_LIST,
    "pull-to-refresh must attach only after the first native list layout",
)
require(
    "ChatThemeStore.shared.activate(chat.id)" in CHAT_DETAIL
    and "chatTheme.activate(chat.id)" not in CHAT_DETAIL,
    "chat appearance must be active before the first rendered frame",
)
require(
    "NativeGlassHeaderMaterial(forcedDark: isDark)" in NAV_GLASS
    and "tint.opacity(isDark ? 0.62 : 0.58)" in NAV_GLASS
    and "value: scrolled > 0" not in NAV_GLASS,
    "the chats top chrome must use same-colour native glass without a first-scroll flash",
)

print("handfeel: passed")
