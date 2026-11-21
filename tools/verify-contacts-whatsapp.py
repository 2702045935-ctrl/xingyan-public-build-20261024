#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VIEW = (ROOT / "Sources" / "ContactsView.swift").read_text(encoding="utf-8")
PHONE = (ROOT / "Sources" / "PhoneContactsView.swift").read_text(encoding="utf-8")
PROFILE = (ROOT / "Sources" / "Profile.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("contacts WeChat verification failed: " + message)


require(
    "private var contactAvatarSize: CGFloat {\n        40" in VIEW
    and ".frame(height: 64)" in VIEW
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
    "nativeQuickIcon(item, size: 30)" in VIEW
    and ".frame(height: 56)" in VIEW
    and ".padding(.leading, 58)" in VIEW,
    "contact utility rows must use compact WeChat-style icon and divider geometry",
)
require(
    ".background(contactsSectionFill)" in VIEW,
    "alphabet headers must stay neutral instead of becoming a green block",
)
require(
    "private var funcStrip" in VIEW
    and "RoundedRectangle(cornerRadius: 16, style: .continuous)" not in VIEW,
    "utility contact entries must use dividers without a surrounding selection card",
)
require(
    'Image(systemName: symbol)' in VIEW
    and "RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)" in VIEW,
    "utility contact icons must use native symbols on a compact colored surface",
)
require(
    "contactSubtitle(" not in VIEW
    and ".frame(height: 36)" in VIEW
    and "RoundedRectangle(cornerRadius: 8, style: .continuous)" in VIEW,
    "contacts must use single-line native rows and the compact WeChat search field",
)
require(
    'Tr("未找到相关联系人")' in VIEW
    and 'Tr("换个关键词试试")' in VIEW,
    "contact search must distinguish an empty result from a missing contact list",
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
