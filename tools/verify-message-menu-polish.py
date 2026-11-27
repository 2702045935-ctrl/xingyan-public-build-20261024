#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MENU = (ROOT / "Sources" / "MessageActions.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("message menu polish verification failed: " + message)


require(
    "struct MsgMenuBox" in MENU
    and "NativeMediaGlassSurface(" in MENU
    and "RoundedRectangle(cornerRadius: 20, style: .continuous)" in MENU
    and "func accent(for action: MsgAction) -> Color" in MENU
    and "action.danger" in MENU
    and "radius: 20, y: 8" in MENU,
    "long-press message menu must use the native premium action tray",
)
require(
    "itemH: CGFloat = 68" in MENU
    and "padding(.horizontal, MsgMenuBox.padH)" in MENU
    and ".padding(.vertical, MsgMenuBox.padV)" in MENU
    and "Circle()\n                                            .fill(accent(for: a).opacity(0.12))"
    in MENU,
    "message menu tiles must use consistent icon medallions and spacing",
)
require(
    "python3 tools/verify-message-menu-polish.py" in WORKFLOW,
    "message menu regression must run in the iOS gate",
)

print("message-menu-polish: passed")
