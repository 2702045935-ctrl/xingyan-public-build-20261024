#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROFILE = (ROOT / "Sources" / "Profile.swift").read_text(encoding="utf-8")

NEW_HEADER = PROFILE.index("var body", PROFILE.index("struct NewFriendsView"))
NEW_HEADER_END = PROFILE.index("private func requestDate", NEW_HEADER)
NEW_ROW = PROFILE.index("private func requestRow", NEW_HEADER_END)
NEW_ROW_END = PROFILE.index("private func doneRow", NEW_ROW)
NEW = PROFILE[NEW_HEADER:NEW_HEADER_END] + PROFILE[NEW_ROW:NEW_ROW_END]

GROUP_START = PROFILE.index("private var participantPicker", PROFILE.index("struct GroupCreateView"))
GROUP_END = PROFILE.index("private var groupDetails", GROUP_START)
GROUP = PROFILE[GROUP_START:GROUP_END]
GROUP_FULL = PROFILE[PROFILE.index("struct GroupCreateView"):GROUP_END]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("contact-flow-layout verification failed: " + message)


require(
    ".frame(height: 44)" in NEW
    and ".frame(height: 36)" in NEW
    and ".frame(height: 30)" in NEW
    and ".frame(height: 60)" in NEW
    and "Avatar(path: user.avatarPath, size: 40, radius: 6)" in NEW
    and ".padding(.leading, 69)" in NEW
    and "private var pageChrome: Color { C.pageBg }" in PROFILE,
    "New Friends must keep the measured 44/36/30/60 pt hierarchy",
)
require(
    "LazyVStack(spacing: 0)" in NEW
    and "OrbitTheme.cardBackground()" not in NEW
    and "RoundedRectangle(cornerRadius: 16" not in NEW,
    "New Friends must be a full-width grouped list without card chrome",
)
require(
    ".frame(height: 44)" in GROUP_FULL
    and "minWidth: 62" in GROUP_FULL
    and "minHeight: 44" in GROUP_FULL
    and ".frame(height: 36)" in GROUP
    and ".frame(height: 33)" in GROUP
    and GROUP.count(".frame(height: 64)") >= 3
    and ".frame(width: 24, height: 24)" in GROUP
    and "Avatar(path: user.avatarPath, size: 40, radius: 6)" in GROUP
    and ".padding(.leading, 16)" in GROUP
    and ".padding(.leading, 109)" in GROUP,
    "New Group must keep the measured 44/36/33/64/24/40/109 pt grid",
)
require(
    "ScrollViewReader" in GROUP
    and "ContactIndexBar(" in GROUP
    and "LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders])" in GROUP
    and "RoundedRectangle(cornerRadius: 16" not in GROUP,
    "New Group must use a lazy sectioned list with native-style indexing",
)
require(
    '"newFriends", "tags", "groups", "chatOnly", "officialAccounts"' in
    (ROOT / "Sources" / "ContactsView.swift").read_text(encoding="utf-8"),
    "Contacts must retain the five-row WeChat utility rhythm",
)

print("contact-flow-layout: passed")
