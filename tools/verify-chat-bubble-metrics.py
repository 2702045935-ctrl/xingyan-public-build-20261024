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
MUSIC_SOURCE = (ROOT / "Sources" / "MusicShare.swift").read_text(
    encoding="utf-8"
)
MALL_SOURCE = (ROOT / "Sources" / "MallShareCard.swift").read_text(
    encoding="utf-8"
)
MINI_SOURCE = (ROOT / "Sources" / "MiniApps.swift").read_text(
    encoding="utf-8"
)
TEXT_ROW = (ROOT / "Sources" / "NativeChatTextRowCell.swift").read_text(
    encoding="utf-8"
)
LAYOUT = (ROOT / "Sources" / "WhatsAppChatLayout.swift").read_text(
    encoding="utf-8"
)
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat bubble metrics verification failed: " + message)


require(
    'static var chatFontSize: CGFloat { o("chatFontSize", 16) }' in CORE
    and 'static var bubblePadH: CGFloat { o("bubblePadH", 13) }' in CORE
    and 'static var bubblePadV: CGFloat { o("bubblePadV", 10) }' in CORE
    and "static var bubblePadH: CGFloat { L.bubblePadH }" in LAYOUT
    and "static var bubblePadV: CGFloat { L.bubblePadV }" in LAYOUT
    and "static let senderHeight: CGFloat = 16" in LAYOUT
    and "L.bubbleMaxW" in LAYOUT
    and 'static var bubbleMaxW: CGFloat { o("bubbleMaxW", min(324, max(252, width * 0.73))) }' in CORE
    and "var radius: CGFloat = WhatsAppChatLayout.cornerRadius" in CHAT,
    "native text geometry must use the stable 11/16 baseline padding and width",
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
    "return 2.5" in CHAT
    and "let isLong = raw.count >= 120" not in CHAT,
    "text line spacing must stay constant within short and long messages",
)
require(
    "senderLabel.frame = CGRect(" in TEXT_ROW
    and "x: bodyX + model.bubblePadH" in TEXT_ROW
    and "metadata.frame = CGRect(" in TEXT_ROW
    and "inlineMetadata" in TEXT_ROW
    and "senderLabel.frame = CGRect(" in MEDIA_ROW
    and "metadata.frame = CGRect(" in MEDIA_ROW
    and ".overlay(alignment: .topLeading)" in CHAT
    and ".overlay(alignment: .bottomTrailing)" in CHAT,
    "sender, text, time and receipts must be laid out inside one WhatsApp bubble",
)
require(
    "Text(TimeFmt.bubble(message.createdAt))" in CHAT
    and ".monospacedDigit()" in CHAT,
    "conversation timestamps must keep stable digits while messages arrive",
)
require(
    "static let cardRadius: CGFloat = WhatsAppChatLayout.cornerRadius" in CARDS
    and "static let mediaRadius: CGFloat = WhatsAppChatLayout.cornerRadius" in CARDS
    and "static let gridRadius: CGFloat = 5" in CARDS
    and ".fill(ChatMessageSurface.cardFill)" in CARDS
    and ".stroke(ChatMessageSurface.cardBorder, lineWidth: 0.5)" in CARDS
    and "if ChatTheme.usesGlass {" in CARDS
    and ".opacity(mine ? 0.84 : 0.74)" in CARDS
    and ".fill(.ultraThinMaterial)" in CARDS
    and ".regularMaterial" not in CARDS,
    "message cards must keep the flat theme and use the glass material when selected",
)
require(
    "static let cornerRadius: CGFloat = 8" in LAYOUT
    and "static let tailDepth: CGFloat = 5" in LAYOUT
    and "static let tailHeight: CGFloat = 9" in LAYOUT
    and "static let tailCenterY: CGFloat = 10.5" in LAYOUT
    and "static let tailInset: CGFloat = tailDepth" in LAYOUT
    and "let out: CGFloat = tail ? WhatsAppChatLayout.tailDepth : 0" in CHAT
    and "let tipY = WhatsAppChatLayout.tailCenterY" in TEXT_ROW
    and "self.verticalPadding = verticalPadding" in CARDS
    and ".padding(.vertical, verticalPadding)" in CARDS,
    "native and SwiftUI bubbles must share the exact tail and vertical inset",
)
require(
    "ChatMessageSurface.mediaRadius" in CHAT
    and ".background(BubbleFill(mine: mine, tail: showTail))" in CHAT
    and ".clipShape(BubbleShape(mine: mine, tail: showTail))" in CHAT
    and "var mine: Bool? = nil" in CARDS
    and "mine: mine,\n            showTail: showTail" in (
        ROOT / "Sources" / "ChatMediaBubbles.swift"
    ).read_text(encoding="utf-8"),
    "chat cards and file cards must reuse the shared bubble shell",
)
require(
    "width: 258" in MEDIA
    and "showTail: showTail" in MEDIA
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
    "let bubbleRail = model.mine" in TEXT_ROW
    and "let bubbleRail = model.mine" in MEDIA_ROW
    and "? bubbleRail - resolved.bubbleWidth + tailInset" in TEXT_ROW
    and "? bubbleRail - bubbleWidth + tailInset" in MEDIA_ROW
    and "model.horizontalMargin + avatarReserve" in TEXT_ROW
    and "model.horizontalMargin + avatarReserve" in MEDIA_ROW
    and "available - avatarReserve" in TEXT_ROW
    and "available - avatarReserve" in MEDIA_ROW,
    "text and media bubbles must share the same left and right alignment rails",
)
require(
    "private var conversationSurface: some View {\n        nativeMessageList" in CHAT
    and "private var shortConversationSurface" not in CHAT
    and "private var legacyNativeMessageList" not in CHAT,
    "every message surface must use the same native edge rail",
)
require(
    "bubblePadHPill" not in CHAT
    and "padding(.horizontal, WhatsAppChatLayout.bubblePadH)" in CHAT
    and "padding(.vertical, WhatsAppChatLayout.bubblePadV)" in CHAT
    and "padding(.horizontal, WhatsAppChatLayout.bubblePadH)" in MEDIA
    and "padding(.vertical, WhatsAppChatLayout.bubblePadV)" in MEDIA,
    "plain text and generic message cards must share one inner padding",
)
require(
    "ShopLinkCard(link: link, mine: mine, showTail: showTail)" in CHAT
    and "MusicBubble(info: m, mine: mine, showTail: showTail)" in CHAT
    and "MallCardBubble(info: m, mine: mine, showTail: showTail)" in CHAT
    and "info: m,\n                    mine: mine,\n                    showTail: showTail" in CHAT
    and "WeChatMessageCard(mine: mine, showTail: showTail)" in (
        ROOT / "Sources" / "ShopLink.swift"
    ).read_text(encoding="utf-8")
    and "WeChatMessageCard(mine: mine, showTail: showTail)" in MUSIC_SOURCE
    and "WeChatMessageCard(mine: mine, showTail: showTail)" in MALL_SOURCE
    and "WeChatMessageCard(mine: mine, showTail: showTail)" in MINI_SOURCE,
    "generic link, music, shop and mini-app cards must share the message bubble shell",
)
require(
    "private let extraImageViews" in MEDIA_ROW
    and "layoutImageGrid(paths: paths, in: body)" in MEDIA_ROW
    and "MultiImageMosaic.frames(count: paths.count, in: body)" in MEDIA_ROW
    and "MultiImageMosaic.visibleCount(for: paths.count)" in MEDIA_ROW,
    "native multi-image messages must render the shared adaptive mosaic",
)
require(
    "private static func imageBubbleSize(" in MEDIA_ROW
    and "var width = min(260, usableWidth)" in MEDIA_ROW
    and "if height > 320" in MEDIA_ROW
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
    and CHAT.count("plain: ChatTheme.preset == .wechat") >= 2
    and "if ChatTheme.preset == .wechat {" in CHAT
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
    "showsAvatar: true" in CHAT
    and "reservesAvatarSpace: true" in CHAT
    and "showTail: isRunStart(message)" in CHAT
    and "showTail: pendingShowsTail(pending)" in CHAT
    and "bubble.showTail = next.showTail" in TEXT_ROW
    and "return displayName(message)" in CHAT
    and "private func pendingShowsAvatar" in CHAT,
    "confirmed rows must keep the stable 11/16 avatar and tail anchors",
)
require(
    'let hidesBubbleMetadata = [\n            "image", "images", "video", "livephoto", "transfer"\n        ].contains(message.kindName)' in CHAT
    and 'metaText: hidesBubbleMetadata ? "" : TimeFmt.messageClock(message.createdAt)' in CHAT
    and "tickCount: hidesBubbleMetadata" in CHAT
    and '!["image", "images", "video", "livephoto", "transfer"]' in CHAT
    and "if showsBubbleMetadata, !senderName.isEmpty" in CHAT
    and "if showsBubbleMetadata {\n                        HStack(spacing: 3)" in CHAT,
    "media and transfer bubbles must omit sender, time and receipt overlays",
)
require(
    ".overlay(alignment: .bottomTrailing)" in CHAT
    and "TimeFmt.messageClock(message.createdAt)" in CHAT
    and "count: deliveryState.tickCount" in CHAT,
    "delivery time and receipt ticks must share the bubble footer",
)
require(
    "return same\n            ? WhatsAppChatLayout.sameRunGap\n            : WhatsAppChatLayout.runGap" in CHAT
    and "static let sameRunGap: CGFloat = 3" in LAYOUT
    and "static let runGap: CGFloat = 9" in LAYOUT,
    "conversation rows must use one WhatsApp run gap in every chat type",
)
require(
    "private static let initialMessageSeed = 240" in CHAT
    and ".suffix(Self.initialMessageSeed)" in CHAT
    and "private let initialMessageWindow = Self.initialMessageSeed" in CHAT,
    "cached, re-entered and refreshed chats must start from the same message window",
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
