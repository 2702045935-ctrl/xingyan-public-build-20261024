#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VIEW = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat menu icon verification failed: " + message)


require(
    'Image(systemName: "line.3.horizontal.decrease.circle")' in VIEW
    and ".font(.system(size: 20, weight: .medium))" in VIEW
    and ".foregroundStyle(ChatListVisual.iconInk)" in VIEW
    and ".buttonStyle(ChatChromeIconPressStyle())" in VIEW,
    "the chats top-right action must match the three-line menu shown above Favorites",
)
require(
    "static let iconInk = Color.dyn(0x3A3A3C, 0xC7C7CC)" in VIEW
    and "static let utilityIconInk = Color.dyn(0x8A8A8E, 0x8E8E93)" in VIEW
    and "Image(systemName: \"magnifyingglass\")\n                    .font(.system(size: 15, weight: .medium))" in VIEW,
    "chat chrome icons must use the restrained system-gray icon hierarchy",
)
require(
    'Image(systemName: "square.and.pencil")' not in VIEW,
    "the old compose icon must not remain in the chats top bar",
)

print("chat-menu-icon: passed")
