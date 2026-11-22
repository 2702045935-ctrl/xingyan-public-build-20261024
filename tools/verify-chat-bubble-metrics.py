#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORE = (ROOT / "Sources" / "Core.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
THEMES = (ROOT / "Sources" / "ChatThemes.swift").read_text(encoding="utf-8")
CARDS = (ROOT / "Sources" / "WeChatMessageCards.swift").read_text(encoding="utf-8")
MEDIA = (ROOT / "Sources" / "ChatMediaBubbles.swift").read_text(encoding="utf-8")
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
    and 'max(232, width * 0.70)' in CORE
    and 'var radius: CGFloat = 7' in CHAT,
    "text-bubble geometry must remain 17pt / 12pt / 70% / 7pt",
)
require(
    'case .wechat: return Color.dyn(0x95EC69, 0x3EB575)' in THEMES
    and "mine ? ChatTheme.mineInk : ChatTheme.ink" in CHAT
    and "preset == .wechat" in CHAT,
    "the classic theme must keep readable dark ink on its light-green bubble",
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
    "static let cardRadius: CGFloat = 8" in CARDS
    and "static let mediaRadius: CGFloat = 6" in CARDS
    and "static let gridRadius: CGFloat = 4" in CARDS
    and ".fill(ChatMessageSurface.cardFill)" in CARDS
    and ".stroke(ChatMessageSurface.cardBorder, lineWidth: 0.5)" in CARDS
    and ".regularMaterial" not in CARDS,
    "WeChat message cards must use the flat 8pt card surface",
)
require(
    "ChatMessageSurface.gridRadius" in CHAT
    and "ChatMessageSurface.mediaRadius" in CHAT
    and "ChatMessageSurface.innerRadius" in CHAT
    and ".fill(mine ? ChatTheme.bubbleMine : ChatMessageSurface.cardFill)" in CHAT
    and ".stroke(mine ? Color.white.opacity(0.08) : ChatMessageSurface.cardBorder"
    in CHAT,
    "image grids, file cards and quotes must share the message surface tokens",
)
require(
    "WeChatMessageCard(width: 258, padding: 0)" in MEDIA
    and "PremiumGlassCard(radius: 18" not in MEDIA
    and "ChatMessageSurface.cardRadius" in MEDIA,
    "contact and upload cards must use the same flat message shell",
)
require(
    'Image(systemName: "ellipsis")' in CHAT
    and ".font(.system(size: 18, weight: .semibold))" in CHAT
    and ".frame(width: 44, height: 44)" in CHAT,
    "the chat overflow control must use restrained dots in a 44pt hit target",
)
require(
    "showsAvatar: true" in CHAT
    and "showTail: true" in CHAT
    and "return displayName(message)" in CHAT
    and 'UIConfig.num("chatDeliveryTicks", 0) > 0' in CHAT,
    "WeChat rows must keep an avatar, tail and sender label on every message",
)
require(
    "var showsDeliveryTicks: Bool = true" in CHAT
    and ".overlay(alignment: .bottomTrailing)" in CHAT
    and ".offset(y: 8)" in CHAT
    and "spacing: senderName.isEmpty ? 0 : 3" in CHAT,
    "delivery ticks must overlay the bubble instead of occupying a separate row",
)
require(
    "let gap: CGFloat = same ? 7 : (isGroup ? 14 : 15)" in CHAT
    and "return mineFor(message) && isRunEnd(message) ? 8 : 4" in CHAT,
    "conversation rows must use close same-sender and distinct cross-sender spacing",
)
require(
    "ChatUnreadRollingBadge(value: unreadHere)" in CHAT
    and 'if unreadHere > 0, !atBottomNow, !initialOpenSettling' in CHAT
    and ".frame(width: 36, height: 36)" in CHAT
    and "Circle().fill(.regularMaterial)" in CHAT,
    "new-message jump control must be a circular unread-only control",
)
require(
    "python3 tools/verify-chat-bubble-metrics.py" in WORKFLOW,
    "chat bubble metrics regression must run in the iOS gate",
)

print("chat-bubble-metrics: passed")
