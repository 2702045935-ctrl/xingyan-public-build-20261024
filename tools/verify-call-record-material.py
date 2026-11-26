#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("call record material verification failed: " + message)


start = CHAT.index("struct CallRecordBubble: View")
end = CHAT.index("\nprivate struct QuoteInspectItem", start)
CARD = CHAT[start:end]

require(
    "BubbleFill(" not in CARD
    and ".fill(.ultraThinMaterial)" in CARD
    and "RoundedRectangle(cornerRadius: 16, style: .continuous)" in CARD
    and "LinearGradient(" in CARD
    and ".stroke(" in CARD,
    "call records must be system event cards using tinted thin material, edge light, and no chat bubble fill",
)
require(
    'Text(message.callText)' in CARD
    and "private var callSubtitle: String" in CARD
    and 'Tr("视频通话")' in CARD
    and 'Tr("语音通话")' in CARD
    and 'mine ? Tr("呼出") : Tr("呼入")' in CARD
    and 'Text(Tr("重拨"))' in CARD,
    "call cards must separate status, media type, direction, and redial action",
)
require(
    "source.contains(\"已取消\")" in CARD
    and "PayVisual.secondaryInk" in CARD
    and "source.contains(\"忙线\")" in CARD
    and "PayVisual.warning" in CARD
    and "message.isBadCallRecord" in CARD
    and "PayVisual.danger" in CARD
    and "PayVisual.success" in CARD,
    "cancelled, missed, busy, and completed calls must keep distinct restrained semantic states",
)
require(
    "python3 tools/verify-call-record-material.py" in WORKFLOW,
    "call record material must run in the iOS gate",
)

print("call-record-material: passed")
