#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
CALL = (ROOT / "Sources" / "CallView.swift").read_text(encoding="utf-8")
LOCATION = (ROOT / "Sources" / "LiveLocation.swift").read_text(encoding="utf-8")
BOTTOM = (ROOT / "Sources" / "BottomSheetSystem.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("location/call polish verification failed: " + message)


require(
    "WhatsAppMessageTicks" not in CHAT
    and "tickCount" not in CHAT,
    "conversation bubbles must not draw delivery checkmarks",
)
require(
    all(token in CHAT for token in (
        "你已取消",
        "对方已取消",
        "未接通",
        "未接听",
        "对方忙线",
        "对方不在线",
        "通话时长 ",
        "phone.arrow.up.right.fill",
    )),
    "call records must distinguish cancelled, missed, rejected, busy, offline and completed states",
)
require(
    "struct CallRecordBubble" in CHAT
    and "BubbleFill(mine: mine, tail: true)" in CHAT
    and "RoundedRectangle(cornerRadius: 11" in CHAT
    and "OrbitTheme.jade" in CHAT,
    "call records must use the unified premium call card",
)
require(
    "struct SendLocationView" in LOCATION
    and "RoundedRectangle(cornerRadius: 26" in LOCATION
    and "LinearGradient(" in LOCATION
    and "GlassBackground" not in LOCATION,
    "send-location must use the production map surface instead of the old glass stack",
)
require(
    "MapAnnotation(coordinate:" in LOCATION
    and "private var floatingHeader" in LOCATION
    and "private var floatingPanel" in LOCATION
    and "一起看位置" in LOCATION
    and "停止共享" in LOCATION,
    "live location must use an immersive map, avatar annotations and a floating control panel",
)
require(
    "struct BottomChoiceSheet: View" in BOTTOM
    and "struct BottomChoiceItem: Identifiable" in BOTTOM
    and "BottomChoiceSheet(" in CHAT
    and ".height(BottomChoiceSheet.preferredHeight(itemCount: 2))" in CHAT
    and ".presentationDetents([.fraction(0.72), .large])" in CHAT
    and ".presentationDetents([.fraction(0.78), .large])" in CHAT
    and ".presentationDetents([.fraction(0.86), .large])" in CHAT
    and ".animation(.spring(response: 0.28, dampingFraction: 0.90),\n                                   value: voiceMode)"
    in CHAT,
    "location choices and secondary location sheets must rise from the bottom like WeChat, with the voice composer using the same motion",
)
require(
    "MapSnapshotView(point: pt, width: 238, height: 144)" in CHAT
    and "mappin.and.ellipse" in CHAT
    and ".background(bubbleFill)" in CHAT
    and "RoundedRectangle(cornerRadius: 14, style: .continuous)" in CHAT
    and "MapSnapshotView(point: pt, width: 216, height: 136)" not in CHAT
    and "BubbleFill(mine: false, tail: showTail)" not in CHAT,
    "sent map cards must use the unified premium map media card",
)
require(
    "private var avatarLayer" in CALL
    and "size: 96," in CALL
    and "radius: 48," in CALL
    and "circle: true" in CALL
    and "statusText" in CALL
    and "bottomBar" in CALL
    and "LinearGradient(" in CALL,
    "voice-call must use the FaceTime-style circular identity and system controls",
)

print("location-call-polish: passed")
