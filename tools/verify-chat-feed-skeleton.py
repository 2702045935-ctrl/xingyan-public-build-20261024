#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat feed skeleton verification failed: " + message)


require(
    "private enum ChatFeedMetrics" in CHAT
    and "static let runGap: CGFloat = 6" in CHAT
    and "static let senderChangeGap: CGFloat = 14" in CHAT
    and "static let systemGap: CGFloat = 12" in CHAT
    and "static let metadataGap: CGFloat = 3" in CHAT
    and "static let statusGap: CGFloat = 3" in CHAT,
    "chat feed must expose one spacing scale",
)
require(
    "showsAvatar: true" in CHAT
    and "if mine {\n                Spacer().frame(width: ChatFeedMetrics.avatarGap)"
    in CHAT
    and "else if reservesAvatarSpace" in CHAT,
    "both sides must preserve a visible avatar on every message",
)
require(
    "return same ? ChatFeedMetrics.runGap : ChatFeedMetrics.senderChangeGap"
    in CHAT
    and "return same ? 3 : 14" not in CHAT
    and 'UIConfig.num("msgGapSame", 6)' not in CHAT
    and 'UIConfig.num("msgGapOther", 16)' not in CHAT,
    "direct and group chats must use one sender-run gap rule",
)
require(
    "private func pendingIsRunStart" in CHAT
    and ".padding(.horizontal,\n                                 ChatFeedMetrics.textHorizontalPadding)"
    in CHAT
    and ".padding(.vertical,\n                                 ChatFeedMetrics.textVerticalPadding)"
    in CHAT
    and "Avatar(path: myAvatarPath," in CHAT
    and "private func pendingGapAfter" in CHAT
    and "private func pendingTextLineSpacing" in CHAT
    and "WhatsAppMessageTicks(count: 1," not in CHAT,
    "pending messages must use the same row, avatar and spacing skeleton without checkmarks",
)
require(
    "L.bubblePadHPill" not in CHAT
    and "L.bubblePadV" not in CHAT
    and "ChatFeedMetrics.textHorizontalPadding" in CHAT
    and "ChatFeedMetrics.textVerticalPadding" in CHAT,
    "text-like messages must not retain their own padding implementation",
)
require(
    "python3 tools/verify-chat-feed-skeleton.py" in WORKFLOW,
    "chat feed skeleton regression must run in the iOS gate",
)

print("chat-feed-skeleton: passed")
