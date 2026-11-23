#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORE = (ROOT / "Sources" / "Core.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
THEMES = (ROOT / "Sources" / "ChatThemes.swift").read_text(encoding="utf-8")
CARDS = (ROOT / "Sources" / "WeChatMessageCards.swift").read_text(encoding="utf-8")
MEDIA = (ROOT / "Sources" / "ChatMediaBubbles.swift").read_text(encoding="utf-8")
MEDIA_ROW = (ROOT / "Sources" / "NativeChatMediaRowCell.swift").read_text(
    encoding="utf-8"
)
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
    and "private var activeGlass: Bool { glass || ChatTheme.usesGlass }" in CHAT
    and "if activeGlass {" in CHAT
    and "ChatSurfaceMaterial.bubble(" in CHAT
    and ".fill(surface.fill)" in CHAT
    and "BubbleFill(mine: mine, tail: showTail, glass: false)" in CHAT,
    "classic bubbles must stay flat while the glass preset opts into translucent fills",
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
    and "if ChatTheme.usesGlass {" in CARDS
    and ".opacity(mine ? 0.84 : 0.74)" in CARDS
    and ".fill(.ultraThinMaterial)" in CARDS
    and ".regularMaterial" not in CARDS,
    "message cards must keep the flat theme and use the glass material when selected",
)
require(
    "ChatMessageSurface.mediaRadius" in CHAT
    and "ChatMessageSurface.innerRadius" in CHAT
    and ".fill(ChatMessageSurface.cardFill(mine: mine))" in CHAT
    and ".stroke(ChatMessageSurface.cardBorder," in CHAT,
    "media cards, file cards and quotes must share the message surface tokens",
)
require(
    "WeChatMessageCard(width: 258, padding: 0)" in MEDIA
    and "PremiumGlassCard(radius: 18" not in MEDIA
    and "ChatMessageSurface.cardRadius" in MEDIA,
    "contact and upload cards must use the same flat message shell",
)
require(
    "x: bubble.frame.minX + (model.mine ? 0 : tailInset)" in MEDIA_ROW
    and "y: bubble.frame.minY" in MEDIA_ROW
    and "width: max(1, bubbleWidth - tailInset)" in MEDIA_ROW
    and "imageView.frame = body" in MEDIA_ROW,
    "native media content must stay anchored inside its message bubble",
)
require(
    "model.horizontalMargin + available - resolved.bubbleWidth" in (
        ROOT / "Sources" / "NativeChatTextRowCell.swift"
    ).read_text(encoding="utf-8")
    and "model.horizontalMargin + available - bubbleWidth" in MEDIA_ROW
    and "model.horizontalMargin + avatarReserve" in (
        ROOT / "Sources" / "NativeChatTextRowCell.swift"
    ).read_text(encoding="utf-8")
    and "model.horizontalMargin + avatarReserve" in MEDIA_ROW
    and "available - avatarReserve" in (
        ROOT / "Sources" / "NativeChatTextRowCell.swift"
    ).read_text(encoding="utf-8")
    and "available - avatarReserve" in MEDIA_ROW,
    "text and media bubbles must share the same left and right alignment rails",
)
short_start = CHAT.index("private var shortConversationSurface")
short_end = CHAT.index("private func scrollShortConversationToBottom", short_start)
short_surface = CHAT[short_start:short_end]
require(
    ".padding(.horizontal, L.msgPad)" not in short_surface
    and ".padding(.trailing, 6)" not in short_surface,
    "short conversations must use one shared edge rail for text, pending and upload bubbles",
)
require(
    "private let extraImageViews" in MEDIA_ROW
    and "layoutImageGrid(paths: paths, in: body)" in MEDIA_ROW
    and "MultiImageMosaic.frames(count: paths.count, in: body)" in MEDIA_ROW
    and "MultiImageMosaic.visibleCount(for: paths.count)" in MEDIA_ROW,
    "native multi-image messages must render the shared adaptive mosaic",
)
require(
    "ImageBubble.thumb(pixel)" in MEDIA_ROW
    and "ImageBubble.looksLikeSticker(pixel)" in MEDIA_ROW
    and "229 + tail" in MEDIA_ROW
    and "case .video(_, _, let w, let h):" in MEDIA_ROW
    and "videoBubbleSize(w: w, h: h)" in MEDIA_ROW
    and "media = .video(cover: cover, seconds: seconds, w: width, h: height)" in CHAT,
    "native image and video rows must preserve the original SwiftUI media sizes",
)
require(
    "private func needsSwiftUIRichText(_ raw: String) -> Bool" in CHAT
    and 'lower.contains("https://")' in CHAT
    and "!needsSwiftUIRichText(message.body)" in CHAT
    and "private var chatOpenURLAction: OpenURLAction" in CHAT
    and ".environment(\\.openURL, chatOpenURLAction)" in CHAT
    and "let line = ceil(pfUIFont(11.5).lineHeight)" in (
        ROOT / "Sources" / "NativeChatTextRowCell.swift"
    ).read_text(encoding="utf-8")
    and "plain ? max(28, line + 8) : max(34, line + 18)" in (
        ROOT / "Sources" / "NativeChatTextRowCell.swift"
    ).read_text(encoding="utf-8")
    and "private let blur = UIVisualEffectView(effect: nil)" in (
        ROOT / "Sources" / "NativeChatTextRowCell.swift"
    ).read_text(encoding="utf-8")
    and "capsule.isHidden = plain" in (
        ROOT / "Sources" / "NativeChatTextRowCell.swift"
    ).read_text(encoding="utf-8")
    and "plain: isGroup || usesPlainDefaultChatChrome" in CHAT
    and "label.sizeThatFits(" in (
        ROOT / "Sources" / "NativeChatTextRowCell.swift"
    ).read_text(encoding="utf-8")
    and ".fill(.ultraThinMaterial)" in CHAT,
    "rich text, links and timestamp rows must keep adaptive SwiftUI sizing and in-app routing",
)
require(
    "case .file:\n                            openFile(message.body)" in CHAT
    and "path.hasPrefix(\"data:\")" in CHAT
    and "private func openInlineFile(dataURL: String, name: String)" in CHAT,
    "file cards must open both remote and inline test documents",
)
require(
    'Image(systemName: "ellipsis")' in CHAT
    and ".font(.system(size: 18, weight: .semibold))" in CHAT
    and ".frame(width: 44, height: 44)" in CHAT,
    "the chat overflow control must use restrained dots in a 44pt hit target",
)
require(
    "showsAvatar: !mine && isRunStart(message)" in CHAT
    and "reservesAvatarSpace: !mine" in CHAT
    and "showsAvatar: !mineFor(message) && isRunStart(message)" in CHAT
    and "reservesAvatarSpace: !mineFor(message)" in CHAT
    and "showTail: !ChatTheme.usesGlass && isRunEnd(message)" in CHAT
    and "showTail: pendingShowsTail(pending)" in CHAT
    and "guard !ChatTheme.usesGlass else { return false }" in CHAT
    and "bubble.showTail = next.showTail" in (
        ROOT / "Sources" / "NativeChatTextRowCell.swift"
    ).read_text(encoding="utf-8")
    and "return displayName(message)" in CHAT
    and 'UIConfig.num("chatDeliveryTicks", 0) > 0' in CHAT,
    "legacy rows keep run-end tails while glass bubbles stay uniform capsules",
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
    "ChatUnreadRollingBadge" not in CHAT
    and ".contentTransition(.numericText" not in CHAT
    and 'if !atBottomNow, !initialOpenSettling' in CHAT
    and "\\(unreadHere) 条新消息" in CHAT
    and "Capsule().fill(.regularMaterial)" in CHAT,
    "the jump control must keep the cheaper text capsule without rolling-number animations",
)
require(
    "python3 tools/verify-chat-bubble-metrics.py" in WORKFLOW,
    "chat bubble metrics regression must run in the iOS gate",
)

print("chat-bubble-metrics: passed")
