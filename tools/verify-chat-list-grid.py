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
    "static let trailing: CGFloat = 17" in CHATS
    and "static let minimumTimeWidth: CGFloat = 52" in CHATS
    and "private let rowTrailing: CGFloat = 17" in NATIVE,
    "native and SwiftUI conversation rows must share the adaptive metadata grid",
)
require(
    "titleRow.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor" in NATIVE
    and "previewTrailingConstraint" in NATIVE
    and "unreadWidthConstraint" in NATIVE
    and "timeMinWidthConstraint" in NATIVE
    and "timeLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor)"
    in NATIVE
    and "titleLabel.frame =" not in NATIVE
    and "layoutTitleBadges" not in NATIVE,
    "conversation metadata must be laid out by Auto Layout, not manual frames",
)
require(
    "max(72, (72 + (combinedScale - 1) * 34).rounded())" in NATIVE
    and "previewLabel.topAnchor.constraint(equalTo: titleRow.bottomAnchor" in NATIVE
    and "private let avatarGap: CGFloat = 12" in NATIVE
    and "textGuide.centerYAnchor.constraint(equalTo: foreground.centerYAnchor" in NATIVE,
    "conversation rows must match the measured 72pt row and tighter line rhythm",
)
require(
    "private func chatListMetaSlot" in CHATS
    and CHATS.count("chatListMetaSlot {") >= 3
    and ".frame(minWidth: ChatListVisual.minimumTimeWidth, alignment: .trailing)" in CHATS,
    "special conversation rows must use the adaptive trailing metadata slot",
)
require(
    "python3 tools/verify-chat-list-grid.py" in WORKFLOW,
    "conversation metadata-grid regression must run in the iOS gate",
)

print("chat-list-grid: passed")
