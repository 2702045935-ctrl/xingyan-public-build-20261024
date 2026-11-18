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
    "gestureRecognizerShouldBegin" in ROW,
    "the avatar interaction must not compete with native row swipes",
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
    "shouldSelectItemAt indexPath: IndexPath" in LIST
    and "dismissOpenSwipeActions()" in LIST,
    "tapping an open row must close actions before opening the chat",
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
    "swipeSelectionGuardUntil" in ROW
    and "consumeSelectionAfterSwipe()" in ROW
    and "consumeSelectionAfterSwipe()" in LIST,
    "a recognized swipe must consume only its short-lived selection callback",
)
require(
    "override func touchesBegan" in ROW
    and "must not eat this fresh row tap" in ROW,
    "a new touch must clear stale swipe-selection suppression",
)
require(
    "Date.timeIntervalSinceReferenceDate + 0.45" in ROW,
    "swipe-selection suppression must expire instead of blocking later taps",
)
require(
    "tap.require(toFail: pan)" in CHATS
    and "shouldRecognizeSimultaneouslyWith" in CHATS,
    "SwiftUI fallback rows must arbitrate tap and pan instead of firing both",
)

print("native-chat-swipe: passed")
