#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def read(path: str) -> str:
    return (ROOT / "Sources" / path).read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("visual settings toast verification failed: " + message)


background = read("ChatBackgroundSheet.swift")
discover = read("DiscoverView.swift")
me = read("MeView.swift")
misc = read("MiscPages.swift")
privacy = read("PrivacyView.swift")
profile = read("Profile.swift")
profile_edit = read("ProfileEditNew.swift")

success_copy = (
    "聊天背景已更新",
    "生活圈封面已更新",
    "作品背景已更新",
    "头像已更新",
    "已恢复默认背景",
    "已改用全局背景",
    "已在本机生效，联网后自动同步",
)

require(
    all(copy not in background for copy in success_copy),
    "chat wallpaper changes must not show success toasts",
)
require(
    all(copy not in discover for copy in success_copy),
    "Moments cover changes must not show success toasts",
)
require(
    all(copy not in me for copy in success_copy)
    and all(copy not in misc for copy in success_copy)
    and all(copy not in privacy for copy in success_copy),
    "profile and theme backgrounds must not show success toasts",
)
require(
    all(copy not in profile for copy in success_copy)
    and all(copy not in profile_edit for copy in success_copy),
    "avatar updates must not show success toasts",
)
require(
    "app.applyMyProfileFields([\"momentCover\": url])" in discover
    and "applySyncedChatBackgrounds(saved)" in background
    and "app.applyMyProfileFields([\"avatar\": url])" in profile,
    "removing success toasts must not remove local-first visual updates",
)
require(
    "python3 tools/verify-visual-settings-toasts.py" in WORKFLOW,
    "visual settings toast regression must run in the iOS gate",
)

print("visual-settings-toasts: passed")
