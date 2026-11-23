#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat first-frame stability failed: " + message)


require(
    "private var initialOpenSettling" in CHAT
    and CHAT.count("if initialOpenSettling { return }") >= 2,
    "first-frame settling must suppress direct and native size-change pinning",
)
require(
    "ChatInitialBottomAnchor(enabled: !initialScrollReady)" in CHAT
    and "defaultScrollAnchor(enabled ? UnitPoint.bottom : nil)" in CHAT
    and "if #available(iOS 17.0, *)" in CHAT
    and "for delay in [0, 24, 70, 150, 260]" not in CHAT,
    "chat entry must use one native bottom anchor instead of repeated visible pinning",
)
require(
    "nativeMessageController.scrollToBottom(animated: false)" in CHAT,
    "native chats must retain their single committed initial bottom placement",
)
require(
    "initialMessageTransaction.disablesAnimations = true" in CHAT
    and "withTransaction(initialMessageTransaction)" in CHAT,
    "the first network page must replace the native list without implicit animation",
)
require(
    "private var usesShortConversationSurface: Bool {\n        // Every conversation" in CHAT
    and "false\n    }" in CHAT,
    "all conversations must use the same native message-list surface",
)
require(
    "private var usesNativeMessageList: Bool" in CHAT
    and "} else {\n            nativeMessageList" in CHAT
    and "initiallyPinnedToBottom: true" in CHAT,
    "long chats must use the premeasured native list to avoid first-scroll stalls",
)
require(
    "private var nativeRowLayoutKey: String" in CHAT
    and "AppFontPrefs.family" in CHAT
    and "nativeRowLayoutKey" in CHAT
    and "asrBusy.contains(message.id) ? \"asr-busy\" : \"\"" in CHAT
    and "deliveryState(for: message).accessibilityText" in CHAT
    and "metaText: TimeFmt.messageClock(message.createdAt)" in CHAT,
    "native row height caches must invalidate on font, layout and visible state changes",
)
require(
    "case timestamp(Message)" in CHAT
    and 'id: "native-time:\\(message.id)"' in CHAT
    and "messageBlock(message, includesTime: false, capturesFrame: false)" in CHAT
    and "accessibilityElement(children: .ignore)" in CHAT
    and "accessibilityLabel(messageAccessibilityLabel(message))" in CHAT,
    "native messages must use separate time rows and one combined semantic row",
)
require(
    "frameForIDHandler" in (ROOT / "Sources" / "NativeStaticList.swift").read_text(
        encoding="utf-8"
    )
    and "nativeMessageController.frameForID(m.id)" in CHAT
    and "capturesFrame: Bool = true" in CHAT,
    "native rows must resolve action anchors on demand instead of observing every frame",
)
NATIVE_LIST = (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8")
require(
    "UICollectionViewDataSourcePrefetching" in NATIVE_LIST
    and "prefetchItemsAt" in NATIVE_LIST
    and "warmHosts" in NATIVE_LIST
    and "takeWarmHost" in NATIVE_LIST
    and "cell.adopt" in NATIVE_LIST,
    "native chat entry must prewarm reusable message hosts before first motion",
)
require(
    "collection.alpha = initiallyPinnedToBottom ? 0 : 1" in (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8")
    and "completeInitialBottom" in (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8"),
    "native chats must reveal only after the first bottom position is committed",
)
require(
    CHAT.count("initialOpenSettling = false") >= 3,
    "settling must end after restore, user interaction, or transition completion",
)
require(
    "python3 tools/verify-chat-first-frame-stability.py" in WORKFLOW,
    "first-frame jump regression must run in the iOS gate",
)

print("chat-first-frame-stability: passed")
