#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORE = (ROOT / "Sources" / "Core.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
THEMES = (ROOT / "Sources" / "ChatThemes.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat bubble metrics verification failed: " + message)


require(
    'static var chatFontSize: CGFloat { o("chatFontSize", 17) }' in CORE
    and 'static var bubblePadH: CGFloat { o("bubblePadH", 9) }' in CORE
    and 'static var bubblePadHPill: CGFloat { bubblePadH + 3 }' in CORE
    and 'max(220, width * 0.66)' in CORE
    and 'var radius: CGFloat = 8' in CHAT,
    "WeChat text-bubble geometry must remain 17pt / 12pt / 66% / 8pt",
)
require(
    'case .whatsapp: return Color.dyn(0x0C7A70, 0x005C4B)' in THEMES
    and "mine ? Color.white.opacity(0.98) : ChatTheme.ink" in CHAT,
    "bubble geometry changes must not change the existing bubble colors",
)
require(
    "var glass: Bool = false" in CHAT
    and "if glass {" in CHAT
    and ".fill(ChatTheme.bubbleMine)" in CHAT
    and "BubbleFill(mine: mine, tail: showTail, glass: false)" in CHAT,
    "bubble surfaces must default to the flat WeChat fill instead of a gradient",
)
require(
    "return min(3.2, max(2.8, L.msgLineSpacing * 0.6))" in CHAT
    and "let isLong = raw.count >= 120" not in CHAT,
    "text line spacing must stay constant within short and long messages",
)
require(
    "Text(TimeFmt.bubble(message.createdAt))" in CHAT
    and ".monospacedDigit()" in CHAT,
    "conversation timestamps must keep stable digits while messages arrive",
)
require(
    'Image(systemName: "ellipsis")' in CHAT
    and ".font(.system(size: 17, weight: .semibold))" in CHAT
    and ".frame(width: 44, height: 44)" in CHAT,
    "the chat overflow control must use WeChat's 17pt dots in a 44pt hit target",
)
require(
    "showsAvatar: !isGroup || mineFor(message) || isRunStart(message)" in CHAT
    and "showsDeliveryTicks: isRunEnd(message)" in CHAT
    and "private func isRunEnd(_ message: Message)" in CHAT,
    "group avatars and delivery ticks must collapse across a continuous message run",
)
require(
    "var showsDeliveryTicks: Bool = true" in CHAT
    and ".overlay(alignment: .bottomTrailing)" in CHAT
    and ".offset(y: 8)" in CHAT
    and "VStack(alignment: mine ? .trailing : .leading, spacing: 4)" in CHAT,
    "delivery ticks must overlay the bubble instead of occupying a separate row",
)
require(
    "same ? 5 : 13" in CHAT
    and "same ? 6 : 15" in CHAT
    and "gap = max(gap, 10)" in CHAT
    and "return mineFor(message) && isRunEnd(message) ? 10 : 4" in CHAT,
    "conversation runs must use distinct WeChat-style same-sender and sender-change spacing",
)
require(
    "python3 tools/verify-chat-bubble-metrics.py" in WORKFLOW,
    "chat bubble metrics regression must run in the iOS gate",
)

print("chat-bubble-metrics: passed")
