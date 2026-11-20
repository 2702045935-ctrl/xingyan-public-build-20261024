#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORE = (ROOT / "Sources" / "Core.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
THEMES = (ROOT / "Sources" / "ChatThemes.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat bubble metrics verification failed: " + message)


require(
    'static var chatFontSize: CGFloat { o("chatFontSize", 17) }' in CORE
    and 'static var bubblePadH: CGFloat { o("bubblePadH", 9) }' in CORE
    and 'static var bubblePadHPill: CGFloat { bubblePadH + 3 }' in CORE
    and 'max(220, width * 0.66)' in CORE
    and 'var radius: CGFloat = 8' in CHAT,
    "WeChat text-bubble geometry must remain 17pt / 12pt / 66% / 8pt",
)
require(
    'case .whatsapp: return Color.dyn(0x0C7A70, 0x005C4B)' in THEMES
    and "mine ? Color.white.opacity(0.98) : ChatTheme.ink" in CHAT,
    "bubble geometry changes must not change the existing bubble colors",
)
require(
    'Image(systemName: "ellipsis")' in CHAT
    and ".font(.system(size: 17, weight: .semibold))" in CHAT
    and ".frame(width: 44, height: 44)" in CHAT,
    "the chat overflow control must use WeChat's 17pt dots in a 44pt hit target",
)
require(
    "python3 tools/verify-chat-bubble-metrics.py" in WORKFLOW,
    "chat bubble metrics regression must run in the iOS gate",
)

print("chat-bubble-metrics: passed")
