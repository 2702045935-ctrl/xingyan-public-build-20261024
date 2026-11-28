#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
THEME = (ROOT / "Sources" / "ChatThemes.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat theme page verification failed: " + message)


require(
    "struct ChatThemePickerView: View" in THEME
    and "List {" in THEME
    and ".listStyle(.insetGrouped)" in THEME
    and ".scrollContentBackground(.hidden)" in THEME
    and ".systemGroupedBackground" in THEME,
    "chat themes must be rebuilt on the native grouped settings hierarchy",
)
require(
    "struct ChatThemeHeroCard: View" in THEME
    and "struct ChatThemeMiniature: View" in THEME
    and "ForEach(ChatAppearancePreset.allCases)" in THEME
    and "listRowSeparator(.hidden)" in THEME
    and "themeRow(preset, isSelected: selected == preset)" in THEME,
    "the page must expose one live preview and system selection rows",
)
require(
    "frame(width: 214, height: 408)" not in THEME
    and "Text(\"9:41\")" not in THEME
    and "RoundedRectangle(cornerRadius: 26, style: .continuous)\n                .stroke(Color.black.opacity(0.82), lineWidth: 5)"
    not in THEME,
    "the legacy phone mockup and decorative status bar must be removed",
)
require(
    "private func select(_ preset: ChatAppearancePreset)" in THEME
    and "store.set(preset, chatId: chatId)" in THEME
    and "UISelectionFeedbackGenerator().selectionChanged()" in THEME
    and "Button(Tr(\"完成\"))" in THEME
    and "store.selected(chatId: chatId)" in THEME,
    "theme selection, persistence, feedback and dismissal must remain immediate",
)
require(
    "python3 tools/verify-chat-theme-page.py" in WORKFLOW,
    "the rebuilt theme page must stay in the iOS gate",
)

print("chat-theme-page: passed")
