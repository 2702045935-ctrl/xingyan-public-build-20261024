#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROFILE = (ROOT / "Sources" / "ProfileEditNew.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("profile system verification failed: " + message)


require(
    "struct ProfileEditView: View" in PROFILE
    and "Form {" in PROFILE
    and ".navigationBarTitleDisplayMode(.large)" in PROFILE,
    "personal information must use the native large-title Form hierarchy",
)
require(
    'nativeValueRow(Tr("我的二维码"), Tr("查看"))' in PROFILE
    and 'Image(systemName: "camera.fill")' in PROFILE
    and "size: 54, radius: 27" in PROFILE,
    "the profile header must expose avatar editing and the account QR entry",
)
require(
    "private var hasUnsavedChanges: Bool" in PROFILE
    and "private var canSave: Bool" in PROFILE
    and ".disabled(!canSave)" in PROFILE
    and '"nickname": cleanNickname' in PROFILE
    and '"patText": cleanPatText' in PROFILE,
    "save must reflect dirty state and submit normalized profile fields",
)

print("profile-info-system: passed")
