#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INFO = (ROOT / "Sources" / "GroupInfoView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat info layout verification failed: " + message)


require(
    "NativeStaticItem(id: \"chat-settings-title\"" in INFO
    and "NativeStaticItem(id: \"tools-title\"" in INFO
    and "ChatInfoSectionTitle(text: Tr(\"聊天工具\"))" in INFO,
    "chat info must use stable native section grouping",
)
require(
    "size: 68, radius: 16" in INFO
    and "Image(systemName: \"qrcode\")" in INFO
    and "HStack(spacing: 14)" in INFO,
    "group identity must use the compact information header",
)
require(
    ".frame(minHeight: 54)" in INFO
    and ".font(pf(16))" in INFO
    and ".padding(.top, 18)" in INFO,
    "chat info rows must use the compact native settings rhythm",
)
require(
    "NativeStaticList(items: directInfoNativeItems" in INFO
    and "private var directInfoNativeItems" in INFO
    and "buttonStyle(MenuPressStyle())" in INFO,
    "single-chat info must share the native list and pressed-row behavior",
)
require(
    "private struct ChatInfoDangerRow" in INFO
    and ".frame(maxWidth: .infinity)\n                .frame(height: AppDesign.Control.dialogRowHeight)" in INFO,
    "destructive chat actions must be isolated as centered red rows",
)
require(
    "python3 tools/verify-chat-info-layout.py" in WORKFLOW,
    "chat info visual hierarchy regression must run in the iOS gate",
)

print("chat-info-layout: passed")
