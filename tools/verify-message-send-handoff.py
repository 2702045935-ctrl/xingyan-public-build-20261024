#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")
NATIVE = (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("message send handoff verification failed: " + message)


start = CHAT.index("if let message = try await API.shared.send(chatId: chat.id, kind: p.kind")
end = CHAT.index("} catch {", start)
block = CHAT[start:end]
remove = block.index("outbox.removeAll { $0.id == p.id }")
append = block.index("appendVisibleMessage(message, pinOwnMessage: false)")
require(remove < append, "local send placeholder must be removed before confirmed bubble insertion")
require(
    "var commitTransaction = Transaction()" in block
    and "commitTransaction.disablesAnimations = true" in block
    and "withTransaction(commitTransaction) {" in block,
    "pending removal and confirmed insertion must commit without animation",
)
require("UINotification.lightTap()" in CHAT, "send action must keep native tactile feedback")
require(
    "pinToBottomSoon(force: true, animated: false)" in CHAT,
    "send action must keep one non-animated bottom pin",
)
require(
    "Task { @MainActor in\n"
    "            // Let the optimistic bubble and keyboard/bottom transaction land\n"
    "            // on screen before transport state starts mutating the queue.\n"
    "            try? await Task.sleep(nanoseconds: 16_000_000)\n"
    "            await flushOutbox()" in CHAT,
    "transport must start after the optimistic bubble has one frame to render",
)

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
    and "Avatar(" in pending
    and "path: app.me?.avatarPath" in pending
    and "private func pendingShowsTail(_ pending: PendingMsg) -> Bool" in CHAT
    and "showTail: pendingShowsTail(pending)" in CHAT,
    "pending and confirmed outgoing bubbles must share the tail rule and self avatar rail",
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
require(
    "func rememberChatPageMessages(" in APP
    and "rememberChatPageMessages(chat.id, cached)" in APP
    and "app.rememberChatPageMessages(chat.id, [message])" in CHAT
    and "app.rememberChatPageMessages(chat.id, snapshot)" in CHAT,
    "confirmed sends and exit/re-entry must merge the current chat page into the in-memory cache",
)
require(
    CHAT.count("app.rememberChatPageMessages(chat.id, [m])") >= 5
    and "app.rememberChatPageMessages(chat.id, [message])" in CHAT
    and "rememberChatPageMessages(c.id, msgs)" in APP
    and "prefetched[c.id] = msgs" not in APP,
    "media sends and stale prefetch snapshots must merge without dropping confirmed rows",
)
require(
    "let index = messages.firstIndex(where: { $0.clientId == cid })" in CHAT
    and "messages[index] = message" in CHAT
    and "if Date() < followOwnSendUntil,\n                       messages.last?.senderId == myId" in CHAT,
    "a confirmed client message must replace its echo and return into view when motion settles",
)
append_start = CHAT.index("private func appendVisibleMessage")
append_end = CHAT.index("private var visiblePendingMessages", append_start)
append_block = CHAT[append_start:append_end]
require(
    append_block.count("guard messages[index] != message else { return }") >= 2
    and "messages[index] = message" in append_block,
    "identical HTTP and WebSocket confirmations must update in place only once",
)
require(
    "private var visiblePendingMessages: [PendingMsg]" in CHAT
    and "let confirmedClientIds = Set(messages.compactMap" in CHAT
    and "return outbox.filter { !confirmedClientIds.contains($0.id) }" in CHAT
    and "for pending in visiblePendingMessages" in CHAT,
    "confirmed messages must structurally suppress matching pending rows in the render projection",
)
require(
    "private func nativeMessageItemID(_ message: Message) -> String" in CHAT
    and 'return "native-outbox:\\(clientId)"' in CHAT
    and "NativeGroupItem(id: nativeMessageItemID(message)" in CHAT
    and 'NativeGroupItem(id: "native-outbox:\\(pending.id)"' in CHAT,
    "confirmed sends must reuse the optimistic collection identity to avoid a row flash",
)
require(
    "let keepsBottomOnItemChange: Bool" in NATIVE
    and "if self.keepsBottomOnItemChange,\n                   wasAtBottom"
    in NATIVE
    and "keepsBottomOnItemChange: true" in CHAT,
    "a tail-row replacement must preserve bottom following in the native message list",
)
require(
    "private func nativeOutboxTextModel(_ pending: PendingMsg)" in CHAT
    and "case .outbox(let pending):\n            return nativeOutboxTextModel(pending) != nil" in CHAT
    and "case .outbox(let pending):\n            guard let model = nativeOutboxTextModel(pending)" in CHAT
    and "bottomGap: 4" in CHAT
    and "showsAvatar: true" in CHAT
    and "withTransaction(sendTransaction)" in CHAT
    and "DispatchQueue.main.async {\n            app.previewOutgoingMessage" in CHAT,
    "plain pending text must use the native row first and defer list-preview work one frame",
)

print("message-send-handoff: passed")
