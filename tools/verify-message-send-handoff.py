#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("message send handoff verification failed: " + message)


start = CHAT.index("if let message = try await API.shared.send(chatId: chat.id, kind: p.kind")
end = CHAT.index("} catch {", start)
block = CHAT[start:end]
remove = block.index("outbox.removeAll { $0.id == p.id }")
append = block.index("appendVisibleMessage(message)")
require(remove < append, "local send placeholder must be removed before confirmed bubble insertion")
require("UINotification.lightTap()" in CHAT, "send action must keep native tactile feedback")
require("pinToBottomSoon(force: true)" in CHAT, "send action must keep bottom pinning")

flush_start = CHAT.index("private func flushOutbox")
flush_end = CHAT.index("private func tapRedPacket", flush_start)
flush_block = CHAT[flush_start:flush_end]
require(
    "while !Task.isCancelled" in flush_block
    and "outbox.first(where: { !$0.sending })" in flush_block,
    "rapid sends must drain newly appended outbox items without another trigger",
)
require(
    "await app.loadChats()" not in flush_block
    and "scheduleChatListRefreshAfterSend()" in flush_block,
    "sending must not block acknowledgement on a full conversation-list refresh",
)
pending_start = CHAT.index("private func pendingBubble")
pending_end = CHAT.index("private func deliveryFailureCard", pending_start)
pending = CHAT[pending_start:pending_end]
require(
    "Text(p.preview)" in pending
    and "BubbleFill(mine: true, tail: showsTail)" in pending
    and "MessageDeliveryState.sent.color" in pending
    and "Avatar(path: app.me?.avatarPath" in pending,
    "pending and confirmed outgoing bubbles must use the same visual structure",
)
send_start = CHAT.index("private func send(kind: String")
send_end = CHAT.index("private func flushOutbox", send_start)
send_block = CHAT[send_start:send_end]
require(
    "app.previewOutgoingMessage(chat" in send_block
    and send_block.find("outbox.append(pending)") < send_block.find(
        "app.previewOutgoingMessage(chat"
    ),
    "the conversation-list preview must update on tap, before network acknowledgement",
)
require(
    "func previewOutgoingMessage(" in APP
    and '"pending-" + clientId' in APP
    and "optimisticChats[chat.id] = row" in APP
    and "optimisticAt[chat.id] = Date()" in APP,
    "pending and confirmed sends must protect the latest list preview from stale snapshots",
)
require(
    "let shouldAdvance = row.lastMessage == nil" in APP
    and "candidateAt > currentAt" in APP
    and "Only a non-regressing" in APP,
    "leaving chat must never overwrite a newer pending summary with messages.last",
)

print("message-send-handoff: passed")
