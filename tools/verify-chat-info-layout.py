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
    "size: 74" in INFO
    and "radius: 20" in INFO
    and "Image(systemName: \"qrcode\")" in INFO
    and "HStack(alignment: .center, spacing: 15)" in INFO,
    "group identity must use the immersive information header",
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
    "private var memberHero" in INFO
    and "private var heroMemberStack" in INFO
    and "memberGridButton(u, size: 56)" in INFO
    and "ForEach(visibleMembers)" in INFO
    and "displayedMemberCount > 20" in INFO
    and "private func memberGridButton" in INFO,
    "group members must use the immersive stack and native member wall",
)
require(
    "private var renameEditor" in INFO
    and "Text(trimmed.isEmpty ? chat.name : trimmed)" in INFO
    and "Text(\"\\(nameDraft.count)/30\")" in INFO
    and "groupToolTile(title:" in INFO
    and "GroupCard(bg: groupSurface)" in INFO,
    "group identity, name editor and settings must share the redesigned hierarchy",
)
require(
    "scheme == .dark ? Color(hex: 0x171A18) : C.cardBg" in INFO
    and "scheme == .dark ? Color(hex: 0x202521)" in INFO
    and "Color.primary.opacity(scheme == .dark ? 0.09 : 0.065)" in INFO,
    "dark group info must use comfortable local surfaces without changing app chrome",
)
require(
    "private struct ChatInfoDangerRow" in INFO
    and "HStack(spacing: 9)" in INFO
    and ".frame(maxWidth: .infinity)\n            .frame(height: 54)" in INFO,
    "destructive chat actions must stay isolated as centered subdued rows",
)
require(
    "python3 tools/verify-chat-info-layout.py" in WORKFLOW,
    "chat info visual hierarchy regression must run in the iOS gate",
)

print("chat-info-layout: passed")
