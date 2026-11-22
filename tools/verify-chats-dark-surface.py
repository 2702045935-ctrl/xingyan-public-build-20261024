#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
ROW = (ROOT / "Sources" / "NativeChatRowCell.swift").read_text(encoding="utf-8")
NATIVE_LIST = (ROOT / "Sources" / "NativeChatList.swift").read_text(encoding="utf-8")
NAV = (ROOT / "Sources" / "NavGlass.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("dark chat surface verification failed: " + message)


require(
    'chatsIsDark ? Color(hex: 0x000000) : C.chatsPageBg' in CHATS,
    "dark chat canvas must use the same true-black surface as native rows",
)
require(
    "showsDivider: true" in CHATS
    and "? UIColor(hex: 0x303030)" in CHATS
    and "dividerColor: isDark\n                ? UIColor(hex: 0x303030)" in CHATS
    and ".fill(ChatListVisual.rule)" in CHATS
    and ".fill(isDark ? Color.clear : ChatListVisual.rule)" not in CHATS
    and "dividerLeading: CGFloat = 77" in ROW,
    "dark chat rows must use the visible 77pt WeChat-sized structural hairline",
)
require(
    'divider.isHidden = !configuration.showsDivider' in ROW,
    "native row cells must apply the divider visibility configuration",
)
require(
    "table.topEdgeEffect.style = .hard" in NATIVE_LIST
    and "table.topEdgeEffect.isHidden = dark" in NATIVE_LIST
    and "controller.tableView.topEdgeEffect.isHidden = dark" in NATIVE_LIST
    and "dark: chatsIsDark" in CHATS,
    "the chat surface must disable the gray system edge effect in dark mode",
)
require(
    "background: chatsPageFill" in CHATS
    and "opacity(scrolled > 0 ? 1 : 0)" in NAV
    and "background ?? (isDark ? Color.black" in NAV,
    "scrolled chat content must disappear behind an opaque top chrome",
)
require(
    "previewLabel.attributedText = nil" in ROW
    and "titleLabel.text = nil" in ROW
    and "foreground.layer.isOpaque = opaque" in ROW
    and "contentView.isOpaque = true" in ROW,
    "reused native rows must clear old text and render on an opaque surface",
)
require(
    "? Color(hex: 0x111111)" in CHATS
    and "Color.white.opacity(0.045)" in CHATS
    and "Color(hex: 0x6E7378)" in CHATS
    and ".stroke(chatsSearchBorder, lineWidth: 0.5)" in CHATS,
    "dark search must sit quietly on pure black instead of using a raised light card",
)
require(
    '"\\(chatsIsDark)-\\(scheme)-\\(Lang.code)' in CHATS,
    "native row signatures must invalidate when the effective theme changes",
)
require(
    "if snapshot.list.isEmpty {\n                    VStack" not in CHATS
    and "private var chatListEmptyState" in CHATS
    and "private var chatListEmptyTitle" in CHATS
    and "private var chatListEmptyDetail" in CHATS
    and ".background(OrbitTheme.canvas)" not in CHATS,
    "empty and filtered chat lists must stay inside the native list surface",
)
require(
    "let previewColor = UIColor(hex: isDark ? 0x7C7C80 : 0x999999)" in CHATS
    and "let timeColor = UIColor(hex: isDark ? 0x5F6368 : 0xB2B2B2)" in CHATS
    and "let titleColor: UIColor = chat.showsOfficialMark" in CHATS
    and "UIColor(hex: isDark ? 0xE9EDEF : 0x191919)" in CHATS,
    "chat-list title, preview and time must use a restrained three-level hierarchy",
)
require(
    "static let avatarSize: CGFloat = 48" in CHATS
    and "static let avatarGap: CGFloat = 13" in CHATS
    and "max(73, (73 + (combinedScale - 1) * 34).rounded())" in ROW
    and "weight: .medium, textStyle: .headline" in ROW,
    "conversation rows must use the tighter WeChat avatar grid and lighter title weight",
)

print("chats-dark-surface: passed")
