#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VIEW = (ROOT / "Sources" / "ContactsView.swift").read_text(encoding="utf-8")
SEARCH_VIEW = VIEW[
    VIEW.index("private var contactsSearchBar"):
    VIEW.index("private var funcStrip")
]
INDEX = (ROOT / "Sources" / "ContactIndex.swift").read_text(encoding="utf-8")
MENU = (ROOT / "Sources" / "MainTab.swift").read_text(encoding="utf-8")
PHONE = (ROOT / "Sources" / "PhoneContactsView.swift").read_text(encoding="utf-8")
PROFILE = (ROOT / "Sources" / "Profile.swift").read_text(encoding="utf-8")
CORE = (ROOT / "Sources" / "Core.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("contacts WeChat verification failed: " + message)


require(
    "@Environment(\\.dynamicTypeSize) private var dynamicTypeSize" in VIEW
    and "contactsAccessibilityScale" in VIEW
    and "private var contactRowHeight: CGFloat" in VIEW
    and ".frame(height: contactRowHeight)" in VIEW
    and ".padding(.leading, 68)" in VIEW,
    "contact rows must use the adaptive 40pt avatar and compact 56pt rhythm",
)
require(
    "private var plusButton" in VIEW
    and "Text(C.tabText1)" in VIEW
    and "systemTextFont(17, .semibold, relativeTo: .headline)" in VIEW,
    "contacts must use a centered native title with the add control on the trailing edge",
)
require(
    "ZStack(alignment: .top)" in VIEW
    and "Color.clear\n                                    .frame(height: contactsHeaderHeight)" in VIEW
    and "contactsSearchBar\n                                    .padding(.horizontal, 16)" in VIEW
    and ".safeAreaInset(edge: .top, spacing: 0)" not in VIEW,
    "contacts search must participate in the native list so it scrolls into the mask",
)
require(
    SEARCH_VIEW.count("RoundedRectangle(cornerRadius: 10, style: .continuous)") >= 2
    and ".fill(contactsSearchFill)" in SEARCH_VIEW
    and "contactsSearchBorder" in SEARCH_VIEW
    and ".overlay(alignment: .bottom)" not in SEARCH_VIEW,
    "contacts search must render as a visible rounded field rather than a divider",
)
require(
    "nativeQuickIcon(item, size: utilityIconSize)" in VIEW
    and "40 * min(1.18, contactsAccessibilityScale)" in VIEW
    and ".frame(height: utilityRowHeight)" in VIEW
    and ".padding(.leading, 69)" in VIEW,
    "contact utility rows must share the 40pt icon and 69pt text column",
)
require(
    ".background(contactsCanvas)" in VIEW
    and ".frame(height: sectionHeaderHeight)" in VIEW,
    "alphabet headers must stay close to the surrounding canvas without a heavy band",
)
require(
    "AvatarSystemEdge(shape: shape)" in CORE
    and "AvatarEdgeFinish" not in CORE
    and "scheme == .dark\n                ? Color.white.opacity(0.09)\n                : Color.black.opacity(0.10)" in CORE
    and "lineWidth: 0.5" in CORE
    and "if level >= 4, size >= 56" in CORE
    and ".shadow(\n            color: size >= 56" not in CORE,
    "list avatars must use system photo cropping, one neutral hairline and no decorative shadow",
)
require(
    "private var funcStrip" in VIEW
    and "RoundedRectangle(cornerRadius: 16, style: .continuous)" not in VIEW,
    "utility contact entries must use dividers without a surrounding selection card",
)
require(
    '"newFriends", "tags", "groups", "chatOnly", "officialAccounts"' in VIEW
    and "Color(hex: 0xFFB340)" in VIEW
    and "Color(hex: 0x8B7CFF)" in VIEW
    and "Color(hex: 0x34C98F)" in VIEW
    and "Color(hex: 0x8B93A1)" in VIEW
    and "Color(hex: 0x58A6FF)" in VIEW
    and "let gradient: LinearGradient" not in VIEW
    and "LinearGradient(\n                        colors: colors" in VIEW
    and ".strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)" in VIEW
    and ".shadow(color: colors.last!.opacity(0.20), radius: 4.5, y: 2)" in VIEW,
    "contact utility icons must use five distinct layered semantic colours",
)
require(
    "enum ContactVisual" in VIEW
    and "static var accent: Color { Color.dyn(0x0F8B65, 0x36CA95) }" in VIEW
    and "static var indexFill: Color { Color.dyn(0x0F8B65, 0x1FAE79) }" in VIEW
    and "ContactVisual.indexFill" in INDEX
    and "ContactVisual.star" in VIEW,
    "contact index, selection and stars must share restrained system accents",
)
require(
    'Text(Tr("搜索联系人"))' in SEARCH_VIEW
    and ".frame(height: searchHeight)" in SEARCH_VIEW
    and ".frame(maxWidth: .infinity)" in SEARCH_VIEW
    and "RoundedRectangle(cornerRadius: 8, style: .continuous)" not in SEARCH_VIEW,
    "contacts must use the centred WeChat search label without a heavy capsule",
)
require(
    'Tr("未找到相关联系人")' in VIEW
    and 'Tr("换个关键词试试")' in VIEW,
    "contact search must distinguish an empty result from a missing contact list",
)
require(
    "private final class NativeContactIndexControl: UIControl" in INDEX
    and "override func beginTracking" in INDEX
    and "override func continueTracking" in INDEX
    and "override func endTracking" in INDEX
    and "override func cancelTracking" in INDEX
    and "UISelectionFeedbackGenerator" in INDEX
    and "nearestAvailableLetter(to: index)" in INDEX
    and "DragGesture" not in INDEX
    and "UIImpactFeedbackGenerator(style: .heavy)" not in INDEX,
    "contact index tracking must use native UIControl events with stable letter slots",
)
require(
    "indexInk: UIColor(Color.dyn(0x4A4A4F, 0xB8BCC2))" in INDEX
    and "accent: UIColor(ContactVisual.indexFill)" in INDEX
    and "activeBubble.backgroundColor = accent" in INDEX
    and "indexInk.withAlphaComponent(isAvailable ? 1 : 0.22)" in INDEX
    and "override func accessibilityIncrement" in INDEX
    and "override func accessibilityDecrement" in INDEX,
    "the native index rail must retain the restrained hierarchy and adjustable accessibility",
)
require(
    "guard activeLetter != letter else { return }" in INDEX
    and INDEX.find("guard activeLetter != letter else { return }") < INDEX.find("onPick(letter)"),
    "index dragging must scroll only when the target letter actually changes",
)
require(
    "ContactAvatarPressStyle" in VIEW
    and "ContactTopIconPressStyle" in VIEW
    and "ContactSearchPressStyle" in VIEW
    and "buttonStyle(ContactSearchPressStyle())" in VIEW
    and "buttonStyle(MenuPressStyle())" in VIEW,
    "contact rows and controls must expose a restrained pressed state",
)
require(
    "withSystemAnimation(.easeOut(duration: 0.12))" not in VIEW
    and 'proxy.scrollTo("letter-\\(L)", anchor: .top)' in VIEW,
    "alphabet index jumps must stay immediate instead of animating across the list",
)
require(
    "case .accessibility1: return 1.10" in VIEW
    and "case .accessibility5: return 1.42" in VIEW
    and "56 * contactsAccessibilityScale" in VIEW
    and "contactsFont(17)" in VIEW
    and "contactsFont(16.5)" in VIEW,
    "contact type and row rhythm must stay fixed until accessibility text sizes",
)
require(
    "opacity(configuration.isPressed ? 0.045 : 0)" in MENU
    and ".easeOut(duration: 0.08)" in MENU
    and ".scaleEffect(configuration.isPressed ? 0.992 : 1)" in MENU
    and "Color.gray.opacity(0.16)" not in MENU,
    "shared menu press feedback must be subtle and animated",
)
require(
    "private var phoneSearchBar" in PHONE
    and 'TextField(Tr("搜索姓名或号码"), text: $keyword)' in PHONE
    and ".frame(height: 64)" in PHONE
    and ".padding(.leading, 74)" in PHONE,
    "phone contacts must use a WhatsApp-style searchable alphabet list",
)
require(
    "private var phonePermissionCard" in PHONE
    and "private func phoneEmptyState" in PHONE
    and "private func phoneAvatarColor" in PHONE
    and 'Image(systemName: "person.crop.circle.badge.plus")' in PHONE,
    "phone contacts must use native permission, empty and invite states",
)
require(
    "private var addFriendActions" in PROFILE
    and "private func addFriendSurface" in PROFILE
    and "private func scheduleSearch" in PROFILE
    and "showPhoneContacts" in PROFILE
    and "showShareInvite" in PROFILE
    and 'NavigationLink(value: "newFriends")' in PROFILE,
    "add-friend page must use WhatsApp-level search, actions and result states",
)

print("contacts-whatsapp: passed")
