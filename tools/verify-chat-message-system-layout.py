#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat message layout verification failed: " + message)


require(
    "private enum MessageRowVisual" in CHAT
    and "static let senderFontSize: CGFloat = 11.5" in CHAT
    and "pf(MessageRowVisual.senderFontSize, .medium)" in CHAT
    and "spacing: MessageRowVisual.columnSpacing" in CHAT
    and "static let sameRunGap: CGFloat = 4" in CHAT
    and "static let runGap: CGFloat = 12" in CHAT,
    "message rows must share one restrained sender and run-spacing grid",
)
require(
    CHAT.count("padding(.horizontal, L.bubblePadH)") >= 8
    and "L.bubblePadHPill" not in CHAT
    and "padding(.vertical, L.bubblePadV)" in CHAT
    and "return 2.5" in CHAT,
    "text and generic cards must use one 13/10 padding and fixed 2.5 line rhythm",
)
require(
    "MessageRowVisual.onlineDot" in CHAT
    and "MessageRowVisual.unreadBadge" in CHAT
    and "MessageRowVisual.sameRunGap" in CHAT
    and "MessageRowVisual.runGap" in CHAT
    and "MessageRowVisual.directSameGap" in CHAT
    and "MessageRowVisual.directRunGap" in CHAT,
    "message status, avatar and vertical rhythm must share the system token set",
)
require(
    "private var usesInlineTextMetadata: Bool" in CHAT
    and "private func textWithInlineMetadata(_ raw: String) -> AttributedString" in CHAT
    and "Text(textWithInlineMetadata(message.body))" in CHAT
    and "Text(textWithInlineMetadata(raw))" in CHAT
    and "showsOutsideDeliveryMetadata" in CHAT
    and '"image", "images", "video", "livephoto", "transfer", "audio"' in CHAT,
    "text metadata must flow with the message while media keeps a clean card",
)
require(
    "min(maxBubbleWidth, max(210, L.width * 0.62))" in CHAT
    and "min(maxBubbleWidth, max(220, L.width * 0.62))" in CHAT
    and "let cardWidth = min(maxBubbleWidth, max(200, L.width * 0.58))" in CHAT
    and "min(maxBubbleWidth, max(210, L.width * 0.56))" in CHAT,
    "cards and utility bubbles must adapt to available screen width",
)
require(
    "python3 tools/verify-chat-message-system-layout.py" in WORKFLOW,
    "chat message layout regression must run in the iOS gate",
)

print("chat-message-system-layout: passed")
