#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)
AUDIO = CHAT.split("private var audioBubble: some View", 1)[1].split(
    "private func voiceClock", 1
)[0]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("WeChat voice bubble verification failed: " + message)


require(
    "min(220, 82 + min(CGFloat(secs), 60) * 2.1)" in AUDIO,
    "voice bubble width must scale by duration within a compact WeChat range",
)
require(
    ".frame(width: width, height: 42, alignment: .leading)" in AUDIO,
    "voice bubble must use the compact WeChat row height",
)
require(
    "voiceSpeakerGlyph(playing: playing)" in AUDIO
    and "speaker.wave.3.fill" in CHAT
    and "speaker.wave.2.fill" in CHAT,
    "voice bubble must use the mirrored speaker glyph instead of a green play orb",
)
require(
    "weChatVoiceClock(total)" in AUDIO
    and 'return "\\(value)″"' in CHAT
    and 'String(format: "%02d″"' in CHAT,
    "voice duration must use WeChat-style seconds and minute marks",
)
require(
    "DragGesture(minimumDistance: 8)" in AUDIO
    and "voicePlayer.seek(to: fraction)" in AUDIO,
    "the compact bubble must still support native scrubbing",
)
require(
    "voiceHoldToken != holdToken || !voiceHoldActive" in CHAT
    and "sendVoice(url: got.url" in CHAT
    and "pendingVoiceURL = got.url" not in CHAT,
    "release must terminate a recording that starts late and send immediately",
)
require(
    "recorder.willCancel ? C.red : OrbitTheme.jadeDeep" in CHAT
    and "Circle().fill(OrbitTheme.jadeDeep)" in CHAT,
    "recording controls must use the fixed Xingyan brand colour",
)
require(
    "python3 tools/verify-voice-bubble-wechat.py" in WORKFLOW,
    "voice bubble regression must run in the iOS gate",
)

print("voice-bubble-wechat: passed")
