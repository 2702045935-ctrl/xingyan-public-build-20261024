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
    and "trailingSwipeActionsConfigurationForRowAt" in LIST
    and "leadingSwipeActionsConfigurationForRowAt" not in LIST
    and "UITableViewDelegate" in LIST,
    "chat rows must use the native table-view trailing swipe actions",
)
require(
    'nativeChatSwipeText("删除", "Delete", "Удалить")' in LIST
    and 'nativeChatSwipeText("不显示", "Hide", "Скрыть")' in LIST
    and '"标为未读"' in LIST
    and "configuration.onDelete()" in LIST
    and "configuration.onHide()" in LIST
    and "configuration.onUnread()" in LIST,
    "left swipe must expose native delete, hide and mark-unread actions",
)
require(
    "deleteAction.backgroundColor = .systemRed" in LIST
    and "hideAction.backgroundColor = .systemGray" in LIST
    and "unreadAction.backgroundColor = .systemBlue" in LIST
    and "swipe.performsFirstActionWithFullSwipe = true" in LIST
    and ".systemOrange" not in LIST,
    "native swipe actions must keep distinct native colors without a pin action",
)
require(
    "func presentNativeChatDeleteConfirmation(from view: UIView?" in LIST
    and "UIAlertController(" in LIST
    and 'style: .destructive' in LIST
    and "presentNativeChatDeleteConfirmation(from: tableView)" in LIST
    and "presentNativeChatDeleteConfirmation(from: self)" in ROW,
    "delete must require a second native destructive confirmation for swipe and accessibility",
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
    "didSelectRowAt indexPath: IndexPath" in LIST,
    "opening a conversation must use UITableView native selection",
)
require(
    "openFromSelection()" in ROW
    and "cell.openFromSelection()" in LIST
    and "openGuardUntil = now + 0.35" in ROW,
    "normal row taps must use table-view selection with a single-open guard",
)
require(
    "contentView.isUserInteractionEnabled = false" in ROW
    and "override func touchesBegan" not in ROW
    and "UIGestureRecognizer" not in ROW
    and "didHighlightRowAt" in LIST
    and "didUnhighlightRowAt" in LIST,
    "native swipe must own row touches; the cell may only render content",
)
require(
    "pressed ? 0.07 : 0.14" in ROW
    and ".beginFromCurrentState" in ROW
    and ".allowUserInteraction" in ROW,
    "native row press feedback must arrive quickly and release without holding the gesture",
)
require(
    "collection.isDirectionalLockEnabled" not in LIST,
    "directional lock must not compete with the system horizontal swipe recognizer",
)
require(
    "rowTap" not in ROW
    and "foreground.addGestureRecognizer(row)" not in ROW
    and "foreground.addGestureRecognizer(tap)" not in ROW,
    "the row must not install a custom tap recognizer over native swipe handling",
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
