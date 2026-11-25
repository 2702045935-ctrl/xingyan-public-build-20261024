#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
NATIVE = (ROOT / "Sources" / "NativeChatRowCell.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat-list-grid verification failed: " + message)


require(
    "static let trailing: CGFloat = 20" in CHATS
    and "static let timeSlotWidth: CGFloat = 68" in CHATS
    and "static let timeSlotGap: CGFloat = 8" in CHATS
    and "private let rowTrailing: CGFloat = 20" in NATIVE
    and "private let timeSlotWidth: CGFloat = 68" in NATIVE
    and "private let timeSlotGap: CGFloat = 8" in NATIVE,
    "native and SwiftUI conversation rows must share the fixed metadata grid",
)
require(
    "bounds.width - textX - rowTrailing - timeSlotWidth - timeSlotGap" in NATIVE
    and "width: titleWidth" in NATIVE
    and "previewReserve" not in NATIVE
    and "cachedTimeWidth" not in NATIVE
    and "timeLabel.adjustsFontSizeToFitWidth = true" in NATIVE,
    "time must not resize the title or preview columns",
)
require(
    "private func chatListMetaSlot" in CHATS
    and CHATS.count("chatListMetaSlot {") >= 3
    and ".frame(width: ChatListVisual.timeSlotWidth, alignment: .trailing)" in CHATS,
    "special conversation rows must reserve the same trailing metadata slot",
)
require(
    "python3 tools/verify-chat-list-grid.py" in WORKFLOW,
    "conversation metadata-grid regression must run in the iOS gate",
)

print("chat-list-grid: passed")
