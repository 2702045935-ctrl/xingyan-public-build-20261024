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
    'mime: "audio/mp4"' in CHAT
    and "skipTranscode: true" in CHAT
    and "uploadBinaryFile(" in CHAT,
    "voice must use the direct binary upload chain before base64 fallback",
)
require(
    "recorder.willCancel ? C.red : OrbitTheme.jadeDeep" in CHAT
    and "Circle().fill(OrbitTheme.jadeDeep)" in CHAT,
    "the hold-to-talk controls must use the fixed Xingyan brand colour",
)
require(
    "private var sentVoiceBubble: some View" in CHAT
    and ".frame(width: width, height: 42, alignment: .leading)" in CHAT
    and "weChatVoiceClock(total)" in CHAT
    and "private var receivedVoiceBubble: some View" in CHAT
    and ".frame(width: width, height: 64, alignment: .leading)" in CHAT
    and "voiceProgressTrack(levels: levels" in CHAT,
    "sent voice bubbles use the compact design while received bubbles stay unchanged",
)
require(
    "python3 tools/verify-voice-hold-brand.py" in WORKFLOW,
    "voice hold and brand regression must run in the iOS gate",
)

print("voice-hold-brand: passed")
