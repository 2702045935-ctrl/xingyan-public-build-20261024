#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VIEW = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
NAV_PLUS = (ROOT / "Sources" / "NavPlusCard.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat menu icon verification failed: " + message)


require(
    "NativeNavMenuButton(" in VIEW
    and 'symbol: "line.3.horizontal.decrease.circle"' in VIEW
    and "tint: UIColor(ChatListVisual.iconInk)" in VIEW
    and ".navPlusOverlay($plusMenu" not in VIEW,
    "the chats top-right action must use the native menu button",
)
require(
    "struct NativeNavMenuButton: UIViewRepresentable" in NAV_PLUS
    and "button.showsMenuAsPrimaryAction = true" in NAV_PLUS
    and "final class NativeNavMenuControl: UIButton" in NAV_PLUS
    and "let glass = UIGlassEffect(style: .regular)" in NAV_PLUS
    and ".systemThinMaterialDark" in NAV_PLUS
    and ".systemThinMaterialLight" in NAV_PLUS
    and "glassView.layer.cornerRadius" in NAV_PLUS
    and "button.menu = UIMenu(" in NAV_PLUS
    and "UIImage(systemName: symbol)" in NAV_PLUS
    and "UIAction(" in NAV_PLUS,
    "the three-line menu must be implemented with a native UIButton and UIMenu",
)
require(
    "static let iconInk = Color.dyn(0x35403A, 0xAEAEB2)" in VIEW
    and "static let utilityIconInk = Color.dyn(0x7A837D, 0x8E8E93)" in VIEW
    and "Image(systemName: \"magnifyingglass\")\n                    .font(.system(size: 15, weight: .medium))" in VIEW,
    "chat chrome icons must use the restrained system-gray icon hierarchy",
)
require(
    'Image(systemName: "square.and.pencil")' not in VIEW,
    "the old compose icon must not remain in the chats top bar",
)

print("chat-menu-icon: passed")
