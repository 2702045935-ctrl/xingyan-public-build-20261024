#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")
INFO = (ROOT / "Sources" / "GroupInfoView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("group announce verification failed: " + message)


require(
    "func applyChatAnnouncementLocally(chatId: String, announce: String)" in APP,
    "the app state must expose a deterministic local announcement update",
)
require(
    "app.applyChatAnnouncementLocally(chatId: chat.id, announce: text)" in INFO,
    "publishing an announcement must update the live chat row immediately",
)
require(
    "_ = try? await API.shared.send(chatId: chat.id, kind: \"announce\"" not in INFO,
    "announcement message failures must not be swallowed",
)
require(
    "群公告已保存，但群消息发送失败" in INFO,
    "a failed announcement message must report a precise error",
)
require(
    "onDelete" in INFO and "删除公告" in INFO,
    "group owners must have an announcement deletion action",
)
require(
    "app.applyChatAnnouncementLocally(chatId: chat.id, announce: \"\")" in INFO,
    "deleting an announcement must clear the live local chat row",
)

print("group-announce: passed")
