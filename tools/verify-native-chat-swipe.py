#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LIST = (ROOT / "Sources" / "NativeChatList.swift").read_text(encoding="utf-8")
ROW = (ROOT / "Sources" / "NativeChatRowCell.swift").read_text(encoding="utf-8")
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("native chat swipe verification failed: " + message)


require(
    "UISwipeActionsConfiguration" in LIST
    and "leadingSwipeActionsConfigurationForItemAt" in LIST
    and "trailingSwipeActionsConfigurationForItemAt" in LIST,
    "chat rows must use native collection-view swipe actions",
)
require(
    "action.backgroundColor = .systemOrange" in LIST
    and "action.backgroundColor = .systemRed" in LIST
    and "swipe.performsFirstActionWithFullSwipe = false" in LIST
    and "swipe.performsFirstActionWithFullSwipe = true" in LIST,
    "right swipe must pin in orange and left swipe must delete in red",
)
require(
    "foreground.addGestureRecognizer(pan)" not in ROW,
    "the custom cell-level horizontal swipe must be removed",
)
require(
    "contextMenuConfigurationForItemAt" not in LIST,
    "chat rows must not keep the old long-press context menu",
)
require(
    "didSelectItemAt indexPath: IndexPath" in LIST,
    "opening a conversation must use UICollectionView native selection",
)
require(
    "foreground.addGestureRecognizer(row)" in ROW
    and "openFromSelection()" in ROW
    and "cell.openFromSelection()" in LIST
    and "openGuardUntil = now + 0.35" in ROW,
    "row taps need a native touch fallback with a single-open guard",
)
require(
    "collection.isDirectionalLockEnabled" not in LIST,
    "directional lock must not compete with the system horizontal swipe recognizer",
)
require(
    "foreground.addGestureRecognizer(tap)" not in ROW,
    "the whole row must not install a child tap recognizer over native swipe handling",
)
require(
    "avatarView.addGestureRecognizer(tap)" in ROW,
    "only the avatar may retain a separate tap recognizer",
)
require(
    "handlePan" not in ROW
    and "pinActions" not in ROW
    and "leftActions" not in ROW
    and "consumeSelectionAfterSwipe" not in LIST,
    "all cell-drawn swipe actions and arbitration state must be deleted",
)
require(
    "tap.require(toFail: pan)" in CHATS
    and "shouldRecognizeSimultaneouslyWith" in CHATS,
    "SwiftUI fallback rows must arbitrate tap and pan instead of firing both",
)

print("native-chat-swipe: passed")
