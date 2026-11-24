#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("voice hold/brand verification failed: " + message)


require(
    "voiceHoldToken != holdToken || !voiceHoldActive" in CHAT
    and "sendVoice(url: got.url" in CHAT
    and "pendingVoiceURL = got.url" not in CHAT,
    "release must terminate a late-starting recording and send immediately",
)
require(
    "recorder.willCancel ? C.red : OrbitTheme.jadeDeep" in CHAT
    and "Circle().fill(OrbitTheme.jadeDeep)" in CHAT,
    "the hold-to-talk controls must use the fixed Xingyan brand colour",
)
require(
    "whatsappVoiceBubble(mine: mine)" in CHAT
    and "private func whatsappVoiceBubble(mine: Bool) -> some View" in CHAT
    and "voicePlayGlyph(playing: playing)" in CHAT
    and "voiceProgressTrack(levels: levels" in CHAT,
    "sent and received voice bubbles must share one compact WhatsApp waveform design",
)
require(
    "message.kindName != \"audio\"" in CHAT
    and "if showsBubbleMetadata," in CHAT,
    "voice bubbles must not render the sender name inside the bubble",
)
require(
    "python3 tools/verify-voice-hold-brand.py" in WORKFLOW,
    "voice hold and brand regression must run in the iOS gate",
)

print("voice-hold-brand: passed")
