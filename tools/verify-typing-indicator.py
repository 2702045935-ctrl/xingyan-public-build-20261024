#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
REALTIME = (ROOT / "Sources" / "Realtime.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("typing-indicator verification failed: " + message)


require(
    "@State private var typingPeers: [String: TypingPeer] = [:]" in CHAT
    and "private struct TypingPeer" in CHAT
    and "private func markPeerTyping(userId: String, nickname: String)" in CHAT
    and "private func clearTyping(_ userId: String? = nil)" in CHAT,
    "typing state must be aggregated per user",
)
require(
    "var nickname = \"\"" in REALTIME
    and 'ev.nickname = (obj["nickname"] as? String) ?? ""' in REALTIME
    and "markPeerTyping(userId: ev.userId, nickname: ev.nickname)" in CHAT,
    "typing events must preserve the sender identity and name",
)
require(
    "private func scheduleTypingExpiry()" in CHAT
    and ".addingTimeInterval(5)" in CHAT
    and "typingPeers.filter { $0.value.updatedAt < cutoff }.keys" in CHAT,
    "typing indicators must expire independently after inactivity",
)
require(
    "private var sortedTypingPeers: [TypingPeer]" in CHAT
    and "if peers.count == 1" in CHAT
    and "if peers.count == 2" in CHAT
    and 'return "\\(peers.count) " + Tr("人正在输入")' in CHAT,
    "group typing state must aggregate one, two and three-plus senders",
)
require(
    "@Environment(\\.accessibilityReduceMotion) private var reduceMotion" in CHAT
    and "if reduceMotion {" in CHAT
    and "TimelineView(.animation(minimumInterval: 1.0 / 30.0))" in CHAT
    and "private var chatTypingIndicator: some View" in CHAT,
    "typing indicator must animate smoothly and respect reduced motion",
)
require(
    "if selectMode { return Tr(\"已选择\") + \" \\(selected.count) \" + Tr(\"项\") }\n        return navTitle"
    in CHAT
    and ".frame(height: 18)" in CHAT
    and ".accessibilityLabel(typingAccessibilityText)" in CHAT,
    "typing must stay in a fixed subtitle rail without replacing the chat title",
)
require(
    "if ev.type == \"typing\", ev.chatId == chat.id" in CHAT
    and "clearTyping(ev.userId.isEmpty ? nil : ev.userId)" in CHAT
    and "typingPeers.removeAll()" in CHAT
    and "Date().timeIntervalSince(lastTypingSent) > 2.0" in CHAT,
    "typing must clear on message/exit and report at a bounded rate",
)
require(
    "python3 tools/verify-typing-indicator.py" in WORKFLOW,
    "typing indicator regression must run in the iOS gate",
)

print("typing-indicator: passed")
