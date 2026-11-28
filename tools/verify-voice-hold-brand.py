#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
FILE_SPEECH = (ROOT / "Sources" / "FileSpeech.swift").read_text(encoding="utf-8")
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
    "private func pendingAudioBubble" in CHAT
    and "pendingAudioBubble(p, tail: isRunStart)" in CHAT
    and 'let stagedPath = "local-voice-\\(UUID().uuidString).\\(ext)"' in CHAT
    and "LocalStore.keepOriginal(stagedPath, from: file)" in CHAT
    and 'send(kind: "audio", content: body)' in CHAT
    and "prepareAudioContentForSend(p.content)" in CHAT
    and 'mime: "audio/mp4"' in CHAT
    and "skipTranscode: true" in CHAT
    and "uploadBinaryFile(" in CHAT
    and "LocalStore.keepOriginal(remote, from: local)" in CHAT,
    "voice must insert a playable local row before a direct binary upload completes",
)
require(
    "recorder.willCancel ? C.red : OrbitTheme.jadeDeep" in CHAT
    and "Circle().fill(OrbitTheme.jadeDeep)" in CHAT,
    "the hold-to-talk controls must use the fixed Xingyan brand colour",
)
require(
    "private var sentVoiceBubble: some View" in CHAT
    and ".frame(width: width, height: 56, alignment: .leading)" in CHAT
    and "weChatVoiceClock(elapsed)" in CHAT
    and "voiceProgressTrack(\n                        levels: levels,\n                        progress: progress,\n                        live: playing\n                    )" in CHAT
    and "private var receivedVoiceBubble: some View" in CHAT
    and ".frame(width: width, height: 70, alignment: .leading)" in CHAT
    and "voiceProgressTrack(levels: levels" in CHAT,
    "sent and received voice bubbles must share the detailed waveform card",
)
require(
    "let inset: CGFloat = 3" in CHAT
    and "let trackWidth = max(18, width - inset * 2)" in CHAT
    and "Capsule(style: .continuous)\n                    .fill(bubblePrimaryInk.opacity(live ? 0.07 : 0.10))"
    in CHAT
    and "Circle()\n                            .fill((mine ? Color.white : C.green).opacity(0.20))"
    in CHAT
    and ".frame(width: 7, height: 7)" in CHAT,
    "voice progress must use an inset track, waveform and luminous playhead",
)
require(
    "python3 tools/verify-voice-hold-brand.py" in WORKFLOW,
    "voice hold and brand regression must run in the iOS gate",
)
require(
    "import Speech" in FILE_SPEECH
    and "SFSpeechRecognizer.requestAuthorization" in FILE_SPEECH
    and "SFSpeechURLRecognitionRequest(url: url)" in FILE_SPEECH
    and "preferOnDevice: false" in FILE_SPEECH
    and "timeout: TimeInterval = 30" in FILE_SPEECH,
    "voice-to-text must use system speech recognition with an online fallback",
)
require(
    "let local = LocalStore.localURL(path)" in CHAT
    and "let localExists = local.map" in CHAT
    and "guard localExists || remote != nil else" in CHAT
    and "if localExists, let local" in CHAT
    and "audioData = try? Data(contentsOf: local)" in CHAT
    and "audioData = try? await API.shared.assetData(remote)" in CHAT
    and "text = await FileSpeech.recognize(url: tmp)" in CHAT,
    "voice-to-text must prefer the local recording before downloading the remote asset",
)

print("voice-hold-brand: passed")
