#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")
TOAST = (ROOT / "Sources" / "AppToastView.swift").read_text(encoding="utf-8")
BACKGROUND = (ROOT / "Sources" / "ChatBackgroundSheet.swift").read_text(encoding="utf-8")
COVER = (ROOT / "Sources" / "DiscoverView.swift").read_text(encoding="utf-8")
PROFILE = (ROOT / "Sources" / "Profile.swift").read_text(encoding="utf-8")
PROFILE_NEW = (ROOT / "Sources" / "ProfileEditNew.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("success toast verification failed: " + message)


require(
    "@Published var toast: AppToastNotice?" in APP
    and "toast = notice" in APP
    and "Task.sleep(\n                nanoseconds: UInt64(notice.duration * 1_000_000_000)"
    in APP,
    "success feedback must render immediately and only use a task for dismissal",
)
require(
    "struct AppToastNotice: Identifiable, Equatable" in TOAST
    and "case .success: return \"checkmark\"" in TOAST
    and ".fill(C.floatingSurface)" in TOAST
    and "RoundedRectangle(cornerRadius: 17" in TOAST
    and "Capsule()" in TOAST
    and "progress = 1" in TOAST,
    "success feedback must use the opaque floating surface, icon and time rail",
)
require(
    "AppToastView(notice: notice)" in APP
    and ".animation(\n                .spring(response: 0.26, dampingFraction: 0.90)"
    in APP,
    "the toast must enter immediately with a short, restrained spring",
)
require(
    "Tr(\"聊天背景已更新\")" not in BACKGROUND
    and "Tr(\"已在本机生效，联网后自动同步\")" not in BACKGROUND
    and "Tr(\"生活圈封面已更新\")" not in COVER
    and "Tr(\"头像已更新\")" not in PROFILE
    and "Tr(\"头像已更新\")" not in PROFILE_NEW,
    "cover, avatar and wallpaper changes must rely on immediate visual feedback without success toasts",
)
for old in [
    "app.show(Tr(\"头像换好了\"))",
    "app.show(Tr(\"聊天背景换好了\"))",
    "app.show(Tr(\"封面换好了\"))",
    "app.show(Tr(\"已在本机换好，联网后自动同步\"))",
]:
    for source in [BACKGROUND, COVER, PROFILE, PROFILE_NEW]:
        require(old not in source, "legacy success copy must not remain in product flows")

require(
    "python3 tools/verify-success-toast.py" in WORKFLOW,
    "success toast regression must run in the iOS gate",
)

print("success-toast: passed")
