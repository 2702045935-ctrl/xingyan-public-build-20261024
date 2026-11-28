#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat rich-text verification failed: " + message)


require(
    "linked[range].font = pfStyled(size: richBaseFontSize, weight: .medium)" in CHAT
    and "linked[range].underlineStyle = .single" in CHAT
    and "private var richBaseFontSize: CGFloat" in CHAT
    and "seg.font = pfStyled(size: richBaseFontSize, weight: .medium)" in CHAT
    and "Color.dyn(0x0068D9, 0x64D2FF)" in CHAT
    and "Color.dyn(0x0F8B65, 0x36CA95)" in CHAT
    and "seg.foregroundColor = bubblePrimaryInk" in CHAT,
    "links, mentions and code-like text must share one adaptive rich-text hierarchy",
)
require(
    'mine ? "mine" : "other"' in CHAT
    and 'senderNameUsesLightInk ? "light" : "adaptive"' in CHAT
    and "ChatTheme.preset.rawValue" in CHAT
    and "currentNickname" in CHAT
    and "currentUsername" in CHAT,
    "rich-text cache keys must include theme, direction, typography and mention identity",
)
require(
    "private func textLineSpacing(_ raw: String) -> CGFloat" in CHAT
    and "let isLong = raw.count >= 120 || lineCount >= 5" in CHAT
    and "padding(.horizontal, ChatFeedMetrics.textHorizontalPadding)" in CHAT
    and "textWithInlineMetadata" not in CHAT
    and "MessageRowVisual" not in CHAT,
    "plain text, images and multi-image layout must remain on the stable baseline",
)
require(
    "ImageBubble(path: message.imagePath" in CHAT
    and "imagesGridBubble" in CHAT
    and "VideoBubble(message: message" in CHAT,
    "image, multi-image and video message rendering must remain unchanged",
)
require(
    "showsAvatar: true" in CHAT
    and "let isRunStart = pendingIsRunStart(p)\n        let showsAvatar = true" in CHAT
    and "return same ? ChatFeedMetrics.runGap : ChatFeedMetrics.senderChangeGap"
    in CHAT
    and "if mine {\n                Spacer().frame(width: ChatFeedMetrics.avatarGap)"
    in CHAT,
    "direct and group messages must share one stable avatar/name run hierarchy",
)
require(
    CHAT.count("NativeMediaGlassSurface") <= 3
    and "NativeGlassControlMaterial()" in CHAT
    and "shape: RoundedRectangle(cornerRadius: 18, style: .continuous),\n                    shadow: true"
    in CHAT,
    "per-row timestamps and media controls must use the 2611280617 lightweight glass",
)
require(
    "static let timeCapsule = Color.dyn(0xD2D1D3, 0x20272A)" in CHAT
    and "static let timeInk = Color.dyn(0x5F5E5F, 0x909396)" in CHAT
    and "NativeGlassControlMaterial()" in CHAT
    and "ChatTheme.timeCapsule.opacity(" in CHAT
    and ".fill(ChatTheme.bubbleMine)" in CHAT
    and ".fill(ChatTheme.bubbleOther)" in CHAT,
    "timestamp capsules must stay lightly translucent while bubbles remain flat",
)
require(
    ".fill(ChatTheme.bubbleMine)" in CHAT
    and ".fill(ChatTheme.bubbleOther)" in CHAT
    and "bubbleGloss" not in CHAT
    and "bubbleShade" not in CHAT
    and "bubbleIridescent" not in CHAT
    and ".fill(C.cardBg)" in CHAT,
    "message surfaces must stay opaque and stable across wallpaper and theme changes",
)
require(
    "python3 tools/verify-chat-message-system-layout.py" in WORKFLOW,
    "chat rich-text regression must run in the iOS gate",
)

print("chat-message-system-layout: passed")
