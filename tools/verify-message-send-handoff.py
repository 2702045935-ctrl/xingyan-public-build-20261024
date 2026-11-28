#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
NATIVE = (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("message send handoff verification failed: " + message)


start = CHAT.index("if let message = try await API.shared.send(")
end = CHAT.index("} catch {", start)
block = CHAT[start:end]
remove = block.index("outbox.removeAll { $0.id == p.id }")
append = block.index("appendVisibleMessage(message)")
require(remove < append, "local send placeholder must be removed before confirmed bubble insertion")
require("UINotification.lightTap()" in CHAT, "send action must keep native tactile feedback")
require(
    "transaction.disablesAnimations = true" in CHAT
    and "withTransaction(transaction) {\n            outbox.append(pending)" in CHAT
    and "prepareForOutgoingTailAppend(\n            following: nativePendingItemID(pending.id)\n        )" in CHAT
    and "app.previewOutgoingMessage(" in CHAT
    and "pendingOutgoingTailID = tailID" in NATIVE
    and "completeOutgoingTailFollowIfNeeded(collection)" in NATIVE
    and "order.contains(where: { String(describing: $0) == tailID })" in NATIVE
    and "if Date() < followOwnSendUntil { return }" in CHAT
    and "pinToBottomImmediately(force: true)\n        pinToBottomSoon(force: true)" not in CHAT
    and "ChatScrollHandle.shared.allowAutomaticPinning()\n                nativeMessageController.scrollToBottom(animated: false)"
    in CHAT,
    "the pending bubble must settle after its native tail row has been laid out",
)
require(
    "func prepareForOutgoingTailAppend(following id: String)" in NATIVE
    and "prepareForOutgoingTailAppendHandler" in NATIVE
    and "collection.isDecelerating" in NATIVE
    and "collection.setContentOffset(collection.contentOffset, animated: false)"
    in NATIVE,
    "outgoing sends must stop inertia through a send-only hook without changing scroll policy",
)
CHAT_SHAPE = CHAT[CHAT.index("struct BubbleShape: Shape"):CHAT.index("private struct BubbleUsesLightInkKey")]
require(
    "let x0 = rect.minX" in CHAT_SHAPE
    and "let x1 = rect.maxX" in CHAT_SHAPE
    and "tipX" not in CHAT_SHAPE
    and "if out > 0" not in CHAT_SHAPE
    and "y0 + h / 2" not in CHAT_SHAPE
    and "clipsToBounds = false" in NATIVE
    and "contentView.clipsToBounds = false" in NATIVE
    and "private let nativeStaticRowDrawingBleed: CGFloat = 0.75" in NATIVE
    and "row(item)\n                    .frame(width: width)\n                    .padding(.vertical, nativeStaticRowDrawingBleed)"
    in NATIVE
    and "row(item)\n                    .frame(maxWidth: .infinity, alignment: .top)\n                    .padding(.vertical, nativeStaticRowDrawingBleed)"
    in NATIVE
    and ".fixedSize(horizontal: false, vertical: true)" in CHAT,
    "bubble tails, text and avatars must keep a measured drawing bleed inside every message cell",
)
require(
    "let prependDetector: (([Item], [Item]) -> Bool)?" in NATIVE
    and "isPrepending = prependDetector(" in NATIVE
    and "premeasure(widthChanged\n                ? nextOrder\n                : Array(Set(changed).union(addedIDs)))"
    in NATIVE
    and "prependDetector: { oldItems, nextItems in" in CHAT
    and "return nextItems.prefix(while: { $0.id != firstKept.id }).contains" in CHAT,
    "pending and confirmed bubbles must use append layout instead of the history prepend path",
)
require(
    "var commit = Transaction(animation: nil)" in CHAT
    and "withTransaction(commit)" in block,
    "confirmed bubbles must replace the pending row in one non-animated transaction",
)
require(
    "private func nativePendingItemID(_ clientId: String) -> String" in CHAT
    and "private func nativeMessageItemID(_ message: Message) -> String" in CHAT
    and "return clientId.isEmpty ? message.id : nativePendingItemID(clientId)" in CHAT
    and "NativeGroupItem(id: nativeMessageItemID(message)" in CHAT
    and "NativeGroupItem(id: nativePendingItemID(pending.id)" in CHAT
    and "following: nativePendingItemID(pending.id)" in CHAT,
    "pending and confirmed bubbles must share one stable native row identity",
)
require(
    'ChatTheme.preset.rawValue' in CHAT
    and "case .outbox(let pending):" in CHAT
    and "themePreset: ChatTheme.preset" in CHAT
    and "lhs.themePreset == rhs.themePreset" in CHAT,
    "visible native message rows must invalidate when the chat theme changes",
)
require(
    "private var quotePrimaryInk: Color" in CHAT
    and "private var quoteSecondaryInk: Color" in CHAT
    and ".foregroundColor(quotePrimaryInk)" in CHAT
    and ".foregroundColor(quoteSecondaryInk)" in CHAT
    and "Color.dyn(0xE8EBED, 0x34383E).opacity(0.96)" in CHAT
    and "Color.dyn(0x343A37, 0xD7DADD)" in CHAT
    and "Color.dyn(0x525A56, 0xBDC1C5)" in CHAT,
    "light quote cards must keep readable sender and summary contrast",
)
require(
    "let pendingText = p.kind == \"text\"" in CHAT
    and "? pendingDisplayText(p.preview)" in CHAT
    and "Text(pendingText)" in CHAT
    and "ClassicEmojiSet.expand(raw)" in CHAT
    and ".trimmingCharacters(in: .whitespacesAndNewlines)" in CHAT
    and ".lineSpacing(pendingTextLineSpacing(pendingText))" in CHAT
    and "private func pendingTextLineSpacing(_ raw: String) -> CGFloat" in CHAT
    and "private func pendingDisplayText(_ raw: String) -> String" in CHAT
    and ".padding(.bottom, pendingGapAfter(p))" in CHAT
    and ".padding(.vertical, 3)\n        .id(p.id)" not in CHAT
    and "insertion: .scale(scale: 0.94" not in CHAT,
    "pending and confirmed text rows must share height and spacing without a scale transition",
)
require(
    "return outbox.isEmpty ? 4 : ChatFeedMetrics.runGap" in CHAT
    and "animated: shouldAnimateAutomaticBottomScroll" in CHAT
    and "Date() >= max(followOwnSendUntil, initialOpenQuietUntil)" in CHAT
    and "animated: Date() < followOwnSendUntil" not in CHAT,
    "outgoing confirmation must preserve the row gap and pin without animation",
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
