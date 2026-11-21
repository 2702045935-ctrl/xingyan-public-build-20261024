#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
ROW = (ROOT / "Sources" / "NativeChatRowCell.swift").read_text(encoding="utf-8")
NATIVE_LIST = (ROOT / "Sources" / "NativeChatList.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("dark chat surface verification failed: " + message)


require(
    'chatsIsDark ? Color(hex: 0x000000) : C.chatsPageBg' in CHATS,
    "dark chat canvas must use the same true-black surface as native rows",
)
require(
    'showsDivider: !isDark' in CHATS,
    "dark native chat rows must disable their divider",
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
    "let previewColor = UIColor(hex: isDark ? 0x7C7C80 : 0xB2B2B2)" in CHATS
    and "let timeColor: UIColor = .tertiaryLabel" in CHATS
    and "let titleColor: UIColor = chat.showsOfficialMark" in CHATS
    and "?: .label" not in CHATS
    and ": .label" in CHATS,
    "chat-list title, preview and time must use adaptive semantic colors",
)

print("chats-dark-surface: passed")
