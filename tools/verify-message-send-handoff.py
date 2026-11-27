#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
NATIVE = (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8")


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
require(
    "transaction.disablesAnimations = true" in CHAT
    and "withTransaction(transaction) {\n            outbox.append(pending)" in CHAT
    and "app.previewOutgoingMessage(" in CHAT
    and "pinToBottomImmediately(force: true)\n        pinToBottomSoon(force: true)" in CHAT
    and "ChatScrollHandle.shared.allowAutomaticPinning()\n                nativeMessageController.scrollToBottom(animated: false)"
    in CHAT,
    "the pending bubble and list preview must appear and pin without an insertion animation delay",
)
require(
    "let prependDetector: (([Item], [Item]) -> Bool)?" in NATIVE
    and "isPrepending = prependDetector(" in NATIVE
    and "premeasure(widthChanged\n                ? nextOrder\n                : Array(Set(changed).union(addedIDs)))"
    in NATIVE
    and "A new outgoing row is a tail-only append" in NATIVE
    and "if isPrepending || commonOrder != order || existingChanged" in NATIVE
    and "prependDetector: { oldItems, nextItems in" in CHAT
    and "return nextItems.prefix(while: { $0.id != firstKept.id }).contains" in CHAT,
    "pending and confirmed bubbles must use append layout instead of the history prepend path",
)
require(
    "var commit = Transaction(animation: nil)" in CHAT
    and "withTransaction(commit)" in block,
    "confirmed bubbles must replace the pending row in one non-animated transaction",
)

flush_start = CHAT.index("private func flushOutbox")
flush_end = CHAT.index("private func tapRedPacket", flush_start)
flush_block = CHAT[flush_start:flush_end]
require(
    "while !Task.isCancelled" in flush_block
    and "outbox.first(where: { !$0.sending })" in flush_block,
    "rapid sends must drain newly appended outbox items without another trigger",
)

print("message-send-handoff: passed")
