#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
REALTIME = (ROOT / "Sources" / "Realtime.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("message receipts verification failed: " + message)


require(
    "parts[2] === 'receipts'" in SERVER
    and "deliveredSeq: allDelivered" in SERVER
    and "readSeq: allRead" in SERVER
    and "const deliveredSeq = Math.max(\n          readSeq," in SERVER,
    "server must expose real per-chat receipt cursors",
)
require(
    "type: 'receipt'" in SERVER
    and "deliveredSeq: seq" in SERVER
    and "readSeq: value" in SERVER,
    "server must publish delivery and read receipt updates",
)
require(
    "func chatReceipts(chatId: String)" in API
    and "struct ChatReceiptSnapshot" in API,
    "client must load receipt state from the server",
)
require(
    "deliveryState: deliveryState(for: message)" in CHAT
    and "case sent" in CHAT
    and "case delivered" in CHAT
    and "case read" in CHAT,
    "message ticks must render the real receipt state",
)
require(
    "WhatsAppMessageTicks(count: 2, color: ChatTheme.readReceipt)" not in CHAT,
    "message ticks must not be hard-coded as delivered",
)
require(
    'var deliveredSeq = 0' in REALTIME
    and 'var readSeq = 0' in REALTIME
    and 'ev.type == "receipt"' in CHAT,
    "realtime receipt updates must reach the open conversation",
)
require(
    "receiptDeliveredSeq" in CHAT
    and "receiptReadSeq" in CHAT
    and "max(receiptDeliveredSeq, recipientDelivered) >= seq" in CHAT,
    "delivery ticks must combine per-recipient and aggregate receipt cursors",
)
require(
    "消息已加密保护" in CHAT
    and "lock.shield.fill" in CHAT
    and "RoundedRectangle(cornerRadius: 12" in CHAT
    and ".fill(.regularMaterial)" in CHAT
    and "Capsule(style: .continuous)\n                .fill(.ultraThinMaterial)" not in CHAT
    and "消息通过加密连接传输，媒体文件加密存储于星言自有服务器。" in CHAT
    and "端到端加密" not in CHAT,
    "security notice must stay readable and accurate without claiming E2EE",
)
require(
    "Color.dyn(0x667781, 0xAEBAC1)" in CHAT
    and "noticeInk.opacity(0.86)" not in CHAT,
    "encrypted notice text must match WhatsApp secondary-text brightness",
)

print("message-receipts: passed")
