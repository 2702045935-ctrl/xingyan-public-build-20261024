#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SETTINGS = (ROOT / "Sources" / "AppleSettingsView.swift").read_text(encoding="utf-8")
SUPPORT = (ROOT / "Sources" / "SupportView.swift").read_text(encoding="utf-8")
FEEDBACK = (ROOT / "Sources" / "FeedbackView.swift").read_text(encoding="utf-8")
TEEN = (ROOT / "Sources" / "TeenCare.swift").read_text(encoding="utf-8")
FONT = (ROOT / "Sources" / "FontSettings.swift").read_text(encoding="utf-8")
WALLPAPER = (ROOT / "Sources" / "ChatBackgroundSheet.swift").read_text(encoding="utf-8")
SHARE = (ROOT / "Sources" / "ShareSheet.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("system settings verification failed: " + message)


require(
    SETTINGS.count('settingsRow(Tr("帮助与反馈")') == 1
    and 'settingsRow(Tr("帮助与客服")' not in SETTINGS,
    "settings must expose one unified Help & Feedback entry",
)
require(
    'Section(Tr("反馈与建议"))' in SUPPORT
    and "FeedbackView()" in SUPPORT
    and "FeedbackHistoryView()" in SUPPORT
    and ".listStyle(.insetGrouped)" in SUPPORT
    and ".searchable(" in SUPPORT,
    "Help & Feedback must combine search, support, feedback and history",
)
require(
    "Form {" in FEEDBACK
    and "Picker(Tr(\"问题类型\")" in FEEDBACK
    and "TextEditor(text: $content)" in FEEDBACK
    and "ScrollView(.horizontal" in FEEDBACK
    and "private var successList: some View" in FEEDBACK
    and "List {" in FEEDBACK
    and "CardGlassBox" not in FEEDBACK,
    "feedback must use native form, picker, editor, attachment and success states",
)
require(
    "Form {" in TEEN
    and "private func teenFeatureIcon" in TEEN
    and "HStack(alignment: .top, spacing: 14)" in TEEN
    and ".navigationTitle(Tr(\"未成年人模式\"))" in TEEN
    and "private var guardianSheet: some View {\n        NavigationStack" in TEEN
    and "CardGlassBox" not in TEEN,
    "teen mode must use native Screen Time-style grouped settings",
)
require(
    "Text(\"Aa\")" in FONT
    and "Slider(" in FONT
    and ".pickerStyle(.segmented)" in FONT
    and "Color.accentColor" in FONT
    and "List {" in FONT,
    "font settings must use the system text-size preview and controls",
)
require(
    "private var standardBody: some View {\n        Form {" in WALLPAPER
    and "backgroundPreview" in WALLPAPER
    and "wallpaperSwatch(item)" in WALLPAPER
    and "originalImage: composingSource" in WALLPAPER
    and "onPreviewPick: beginComposingPreview" in WALLPAPER,
    "chat wallpaper must use native preview, gallery and crop flow",
)
require(
    "private struct ShareActionRow" in SHARE
    and ".background(.regularMaterial)" in SHARE
    and "ShareSheetTheme" in SHARE
    and "UIActivityViewController(activityItems: items" in SHARE,
    "share must use a system action list with the native activity fallback",
)
require(
    "python3 tools/verify-system-settings-pages.py" in WORKFLOW,
    "system settings regression must run in the iOS gate",
)

print("system-settings-pages: passed")
