#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NAV = (ROOT / "Sources" / "NavGlass.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
ROW = (ROOT / "Sources" / "NativeChatRowCell.swift").read_text(encoding="utf-8")
TAB = (ROOT / "Sources" / "NativeTabBar.swift").read_text(encoding="utf-8")
MAIN = (ROOT / "Sources" / "MainTab.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("advanced interactions verification failed: " + message)


require("scheme == .dark ? 0.72 : 0.56" in NAV,
        "scrolled chat-list chrome must occlude text while preserving a light material")
require("private struct MessageReplySwipe" in CHAT
        and "MessageReplySwipe(enabled: !selectMode" in CHAT
        and "quote = message" in CHAT,
        "message rows must support an interruptible swipe-to-reply gesture")
require("selection.wrappedValue == index" in TAB
        and "scrollVisiblePageToTop" in TAB
        and "selectionGlass" not in TAB,
        "native tab bar must keep reselect behavior without an overlay covering labels")
require("scrollVisiblePageToTop" in TAB
        and "StatusBarTapScrollTop" in MAIN,
        "repeated tab selection and status-bar taps must return the active page to top")
require(".chrisRowSwipe" in ROW and "handleSwipeElsewhere" in ROW,
        "opening a chat swipe action must close the previously open row")
require("unreadHere > 0" in CHAT and "条新消息" in CHAT,
        "chat must keep the away-from-bottom new-message pill")

print("advanced-interactions: passed")
