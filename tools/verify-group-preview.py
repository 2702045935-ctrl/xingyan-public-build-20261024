#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
PROFILE = (ROOT / "Sources" / "Profile.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("group preview verification failed: " + message)


require(
    "function lastPreviewMessage(messages)" in SERVER
    and "message.kind === 'system'" in SERVER
    and "!String(message.content || message.preview || '').trim()" in SERVER,
    "empty group system rows must be skipped when choosing the latest preview",
)
require(
    "if raw.isEmpty, isGroupAvatar, chat.lastMessage == nil" in CHATS
    and "else if preview.isEmpty, isGroup, chat.lastMessage == nil" in CHATS,
    "member-count copy is only valid when a group has no last message at all",
)
require(
    "python3 tools/verify-group-preview.py" in WORKFLOW,
    "group preview regression must run in the iOS gate",
)
require(
    "if step == .participants" in PROFILE
    and "groupDetails\n                    .transition(.opacity)" in PROFILE
    and 'Text(Tr("完成"))' in PROFILE
    and "private var participantPicker" in PROFILE,
    "group creation must use the WeChat-style participant then details flow",
)
require(
    "private func defaultGroupName()" in PROFILE
    and "selectedContacts.prefix(3).map(\\.name)" in PROFILE
    and 'Tr("选择一个已有的群")' in PROFILE
    and 'Tr("创建新群聊")' in PROFILE
    and "private func groupOptionRow" in PROFILE,
    "group creation must expose the measured group picker entry points and seed a usable default name",
)
require(
    ".frame(height: 64)" in PROFILE
    and ".padding(.leading, 109)" in PROFILE
    and "buttonStyle(MenuPressStyle())" in PROFILE
    and ".safeAreaInset(edge: .bottom, spacing: 0) { createDock }" not in PROFILE,
    "participant rows must use the 64pt selection grid without the old bottom action dock",
)

print("group-preview: passed")
