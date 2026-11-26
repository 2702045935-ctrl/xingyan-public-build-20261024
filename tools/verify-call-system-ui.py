#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CALL = (ROOT / "Sources" / "CallView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("call system UI verification failed: " + message)


require(
    "Avatar(path: call.peerAvatar, size: 112, radius: 56, circle: true)" in CALL
    and 'font(pfExact(29, .semibold))' in CALL
    and "private var callStatusPill: some View" in CALL
    and ".frame(width: 184, height: 184)" in CALL
    and "Color.black.opacity(0.78)" in CALL,
    "the active call must use a large circular identity with system title and status hierarchy",
)
require(
    "private func systemControl(" in CALL
    and "private func systemCallAction(" in CALL
    and CALL.count(".fill(.ultraThinMaterial)") >= 5
    and "Color.black.opacity(0.22)" in CALL
    and "Color.white.opacity(0.34)" in CALL,
    "call controls must use restrained dark thin-glass material with a visible edge",
)
require(
    "HStack(spacing: 42) {\n                        micKey\n                        if call.phase == .active {\n                            speakerKey\n                        }\n                    }\n\n                    hangupKey" in CALL
    and "HStack(spacing: 51) {\n                            micKey\n                            hangupKey\n                            speakerKey" not in CALL,
    "hangup must be a separate bottom action instead of sitting between microphone and speaker",
)
require(
    "private var callTopGlass: some View" in CALL
    and "private var screen" not in CALL
    and "MarqueeText(text: \"正在等待对方接受邀请…\")" not in CALL
    and 'Tr("正在呼叫…")' in CALL,
    "top controls and call status must shed the old WeChat-style treatment",
)
require(
    "python3 tools/verify-call-system-ui.py" in WORKFLOW,
    "call system UI must run in the iOS gate",
)

print("call-system-ui: passed")
