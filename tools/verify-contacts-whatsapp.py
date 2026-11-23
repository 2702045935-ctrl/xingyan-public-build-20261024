#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VIEW = (ROOT / "Sources" / "ContactsView.swift").read_text(encoding="utf-8")
INDEX = (ROOT / "Sources" / "ContactIndex.swift").read_text(encoding="utf-8")
MENU = (ROOT / "Sources" / "DesignSystem.swift").read_text(encoding="utf-8")
PHONE = (ROOT / "Sources" / "PhoneContactsView.swift").read_text(encoding="utf-8")
PROFILE = (ROOT / "Sources" / "Profile.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("contacts WeChat verification failed: " + message)


require(
    "private var contactAvatarSize: CGFloat {\n        AppDesign.Avatar.row" in VIEW
    and ".frame(height: AppDesign.Control.compactRowHeight)" in VIEW
    and ".padding(.leading, 68)" in VIEW,
    "contact rows must use the compact 40pt avatar and 64pt WeChat-style rhythm",
)
require(
    "private var plusButton" in VIEW
    and "Text(C.tabText1)" in VIEW
    and "systemTextFont(17, .semibold, relativeTo: .headline)" in VIEW,
    "contacts must use a centered native title with the add control on the trailing edge",
)
require(
    "nativeQuickIcon(item, size: 34)" in VIEW
    and "AppFlowRow(height: AppDesign.Control.compactRowHeight)" in VIEW
    and "AppFlowDivider(leading: 62)" in VIEW,
    "contact utility rows must reuse the shared compact row and divider geometry",
)
require(
    ".background(contactsSectionFill)" in VIEW,
    "alphabet headers must stay neutral instead of becoming a green block",
)
require(
    "private var funcStrip" in VIEW
    and "AppFlowPanel {" in VIEW
    and "AppFlowDivider(leading: 62)" in VIEW,
    "utility contact entries must use the shared grouped panel",
)
require(
    'Image(systemName: symbol)' in VIEW
    and "RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)" in VIEW,
    "utility contact icons must use native symbols on a compact colored surface",
)
require(
    "contactSubtitle(" not in VIEW
    and "AppDesign.Control.searchHeight" in VIEW
    and "AppDesign.Radius.control" in VIEW,
    "contacts must use single-line native rows and the shared search field",
)
require(
    'Tr("未找到相关联系人")' in VIEW
    and 'Tr("换个关键词试试")' in VIEW,
    "contact search must distinguish an empty result from a missing contact list",
)
require(
    "private var displayedLetters: [String] { Self.letters }" in INDEX
    and "ForEach(displayedLetters, id: \\.self)" in INDEX
    and "nearestAvailableLetter(to: i)" in INDEX
    and "haptic.selectionChanged()" in INDEX
    and "UIImpactFeedbackGenerator(style: .heavy)" not in INDEX,
    "contact index positions must stay stable and use lightweight selection feedback",
)
require(
    "guard active != letter else { return }" in INDEX
    and INDEX.find("guard active != letter else { return }") < INDEX.find("onPick(letter)"),
    "index dragging must scroll only when the target letter actually changes",
)
require(
    "ContactAvatarPressStyle" not in VIEW
    and "ContactTopIconPressStyle" not in VIEW
    and "ContactSearchPressStyle" not in VIEW
    and "buttonStyle(AppPressStyle())" in VIEW
    and "buttonStyle(MenuPressStyle())" in VIEW,
    "contact rows and controls must expose a restrained pressed state",
)
require(
    "withSystemAnimation(.easeOut(duration: 0.12))" not in VIEW
    and 'proxy.scrollTo("letter-\\(L)", anchor: .top)' in VIEW,
    "alphabet index jumps must stay immediate instead of animating across the list",
)
require(
    "opacity(configuration.isPressed ? 0.045 : 0)" in MENU
    and "AppDesign.Motion.press" in MENU
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
    and "AppFlowPanel {" in PROFILE
    and "AppEmptyState(" in PROFILE
    and "StarOrbitSearchField(" in PROFILE
    and "private func addFriendSurface" not in PROFILE
    and "private func scheduleSearch" in PROFILE
    and "showPhoneContacts" in PROFILE
    and "showShareInvite" in PROFILE
    and 'NavigationLink(value: "newFriends")' in PROFILE,
    "add-friend page must use WhatsApp-level search, actions and result states",
)

print("contacts-whatsapp: passed")
