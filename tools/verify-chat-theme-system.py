#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
THEMES = (ROOT / "Sources" / "ChatThemes.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
GROUP_INFO = (ROOT / "Sources" / "GroupInfoView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat theme system verification failed: " + message)


require(
    "List {" in THEMES
    and ".listStyle(.insetGrouped)" in THEMES
    and "Section {" in THEMES,
    "the chat theme page must use a native inset-grouped settings hierarchy",
)
require(
    "themePreview(selected)" in THEMES
    and ".frame(maxWidth: .infinity)" in THEMES
    and ".frame(height: 214)" in THEMES,
    "the current theme must render as a responsive full-width overview",
)
require(
    "store.set(preset, chatId: chatId)" in THEMES
    and "ChatThemeStore.shared.refresh(chat.id)" in GROUP_INFO,
    "theme selection must keep the existing persistence and immediate refresh path",
)
require(
    "WhatsAppMessageTicks" not in CHAT,
    "the chat message stream must not render checkmark delivery ticks",
)

print("chat-theme-system: passed")
