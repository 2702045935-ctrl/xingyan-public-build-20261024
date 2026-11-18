#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
ROW = (ROOT / "Sources" / "NativeChatRowCell.swift").read_text(encoding="utf-8")


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
    'activeBaseOpacity: chatsIsDark ? 0.94 : nil' in CHATS,
    "dark scroll mask must use the shared near-opaque chat canvas",
)
require(
    '"\\(chatsIsDark)-\\(scheme)-\\(Lang.code)' in CHATS,
    "native row signatures must invalidate when the effective theme changes",
)
require(
    "let previewColor: UIColor = .secondaryLabel" in CHATS
    and "let timeColor: UIColor = .tertiaryLabel" in CHATS
    and "let titleColor: UIColor = chat.showsOfficialMark" in CHATS
    and "?: .label" not in CHATS
    and ": .label" in CHATS,
    "chat-list title, preview and time must use adaptive semantic colors",
)

print("chats-dark-surface: passed")
