#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DETAIL = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
LIST = (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8")
TEXT_ROW = (ROOT / "Sources" / "NativeChatTextRowCell.swift").read_text(encoding="utf-8")
MEDIA_ROW = (ROOT / "Sources" / "NativeChatMediaRowCell.swift").read_text(encoding="utf-8")
LINK = (ROOT / "Sources" / "ShopLink.swift").read_text(encoding="utf-8")
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat motion/link verification failed: " + message)


require(
    "if p.sending {\n                    ProgressView()" not in DETAIL,
    "an outgoing text bubble must not flash a server spinner",
)
require(
    "withAnimation(.spring(response: 0.24" in DETAIL
    and "outbox.append(pending)" in DETAIL,
    "optimistic outgoing bubbles must enter with the Apple spring",
)
require(
    "persistOutboxAfterFrame()" in DETAIL,
    "outbox persistence must yield the first frame before disk I/O",
)
require(
    "initiallyPinnedToBottom: true" in DETAIL
    and "waitsForInitialBottom" in LIST
    and "setBottom(collection, animated: false)" in LIST,
    "group chat must position its native list before presentation",
)
require(
    '"outbox",' in DETAIL
    and 'pending.failed ? "failed" : "ok"' in DETAIL,
    "sending state must not invalidate or remeasure an unchanged bubble",
)
require(
    "officialRowTime(\"official\")" in CHATS
    and "officialRowTime(\"pay\")" in CHATS
    and "officialRowTime(\"weather\")" in CHATS,
    "official account rows must use conversation time instead of chevrons",
)
require(
    "withAnimation(chatKeyboardAnimation(n)) { kbHeight = h }" in DETAIL
    and "keyboardAnimationDurationUserInfoKey" in DETAIL
    and "keyboardAnimationCurveUserInfoKey" in DETAIL
    and "private func openActions(_ m: Message, bubbleFrame: CGRect? = nil)" in DETAIL
    and "onLongPress: { [weak view] in" in DETAIL,
    "composer and message menus must follow native keyboard and bubble geometry",
)
require(
    "final class NativeChatTextRowView: UIView, UIGestureRecognizerDelegate" in TEXT_ROW
    and "final class NativeChatMediaRowView: UIView, UIGestureRecognizerDelegate" in MEDIA_ROW
    and "bubble.frame.contains(touch.location(in: self))" in TEXT_ROW
    and "bubble.frame.contains(touch.location(in: self))" in MEDIA_ROW
    and "private var longPressRecognizer" in MEDIA_ROW
    and "func bubbleWindowFrame() -> CGRect" in TEXT_ROW
    and "func bubbleWindowFrame() -> CGRect" in MEDIA_ROW,
    "native message gestures must start on the bubble and media rows must support long press",
)
require(
    "var displayHost: String" in LINK
    and "var visibleSubtitle: String" in LINK
    and "var footerTitle: String" in LINK
    and "private let linkAccent" in LINK,
    "shared links must expose a high-contrast host to every recipient",
)
require(
    "0x0056D6" in DETAIL,
    "plain chat links must use the stronger recipient-side blue",
)
require(
    "count: deliveryState.tickCount" in DETAIL
    and "WhatsAppMessageTicks(" in DETAIL
    and "self == .sent ? 1 : 2" in DETAIL
    and "static let readReceipt = Color(hex: 0x53BDEB)" in DETAIL,
    "outgoing messages must use single and WhatsApp-style double ticks",
)
require(
    "friendlyServerMessage" in API
    and "服务器返回了看不懂的内容" not in API
    and "数据解析失败" not in API,
    "technical server failures must be converted into user-readable copy",
)
require(
    "patPreviewText" in CHATS
    and 'case "pat": return sessionCopy(zh: "拍了拍"' in CHATS,
    "pat previews must never expose star-light implementation language",
)
require(
    "localMessagePreview" in APP
    and "return message.body.isEmpty ? \"[消息]\" : message.body" not in APP,
    "realtime and first-send previews must never fall back to raw payload JSON",
)

print("chat-motion-link: passed")
