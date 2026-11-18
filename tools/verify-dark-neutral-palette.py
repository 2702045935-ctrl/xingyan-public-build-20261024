#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ROW = (ROOT / "Sources" / "NativeChatRowCell.swift").read_text(encoding="utf-8")
TAB = (ROOT / "Sources" / "NativeTabBar.swift").read_text(encoding="utf-8")
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("dark neutral palette verification failed: " + message)


require("let interactionAccent = UIColor(OrbitTheme.jade)" in TAB
        and "bar.tintColor = interactionAccent" in TAB
        and "selected.iconColor = interactionAccent" in TAB
        and "UIColor.systemBlue" not in TAB,
        "dark tab bar must use one brand accent instead of mixed system colors")
require(ROW.count("if !isLight { return nil }") >= 2
        and "previewTokenColor(token," in ROW
        and "previewKindColor(kind," in ROW,
        "dark chat previews must collapse secondary type colors to neutral ink")
require("unreadLabel.backgroundColor = .systemRed" in ROW
        and "systemBlue" not in CHATS,
        "unread counts must use the single red badge language")

print("dark-neutral-palette: passed")
