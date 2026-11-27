#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORE = (ROOT / "Sources" / "Core.swift").read_text(encoding="utf-8")
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
ROW = (ROOT / "Sources" / "NativeChatRowCell.swift").read_text(encoding="utf-8")
NAV = (ROOT / "Sources" / "NavGlass.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
TAB = (ROOT / "Sources" / "NativeTabBar.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("daylight-jade verification failed: " + message)


for token in (
    'UIConfig.fixedDark("pageBg", 0xF2F4F1, 0x101412)',
    'UIConfig.fixedDark("cardBg", 0xFAFBF9, 0x1D231F)',
    'UIConfig.fixedDark("chatsRowBg", 0xFAFBF9, 0x171B18)',
    'UIConfig.fixedDark("previewColor", 0x626B66, 0xA5ACA8)',
    'UIConfig.fixedDark("timeColor", 0x858D88, 0x747C78)',
    'UIConfig.fixedDark("lineColor", 0xDDE2DD, 0x2A302C)',
):
    require(token in CORE, "missing shared daylight-jade token: " + token)

require(
    "Color(hex: 0x101412)" in CHATS
    and "Color(hex: 0x171B18)" in CHATS
    and "UIColor(hex: isDark ? 0xA5ACA8 : 0x626B66)" in CHATS
    and "UIColor(hex: isDark ? 0x747C78 : 0x858D88)" in CHATS,
    "conversation surfaces must retain the four-level light/dark hierarchy",
)
require(
    "weight: .semibold, textStyle: .headline" in ROW
    and "titleRow.transform = CGAffineTransform(translationX: 0, y: -1)" in ROW,
    "conversation title must use the calibrated semibold optical rhythm",
)
require(
    "final class SpecularEffectView" in NAV
    and "topSheen.colors" in NAV
    and "diagonalSheen.colors" in NAV
    and "lowerShade.colors" in NAV
    and "shape.stroke(\n                LinearGradient(" in NAV,
    "native glass must provide specular, diagonal and lower-rim response",
)
require(
    "NativeGlassHeaderMaterial(forcedDark: lightInk)" in CHAT
    and "Color.white.opacity(effectiveDark ? 0.055 : 0.13)" in CHAT
    and "Color.black.opacity(effectiveDark ? 0.10 : 0.018)" in CHAT,
    "chat edge masks must provide light and dark mirror response",
)
require(
    "Color.dyn(0x757D78, 0x8B938E)" in TAB
    and "Color.dyn(0x117A58, 0x42C693)" in TAB,
    "tab icons must share the new neutral and jade hierarchy",
)
require(
    "Color.clear\n                        .frame(height: L.safeTop + chatsHeaderH + chatsSearchH)"
    in CHATS
    and "chatTopHeader\n                        .background" in CHATS,
    "top material must stop above the search row",
)
require(
    "python3 tools/verify-daylight-jade.py" in WORKFLOW,
    "the visual system regression must run in the iOS gate",
)

print("daylight-jade: passed")
