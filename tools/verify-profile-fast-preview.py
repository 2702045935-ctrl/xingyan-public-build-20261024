#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROFILE = (ROOT / "Sources" / "Profile.swift").read_text(encoding="utf-8")
EDIT = (ROOT / "Sources" / "ProfileEditNew.swift").read_text(encoding="utf-8")
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("profile fast-preview verification failed: " + message)


for name, source in (("profile", PROFILE), ("profile-edit", EDIT)):
    apply = source.index('app.applyMyProfileFields(["avatar": localPath])')
    idle = source.index("busy = false", apply)
    network = source.index("Task {", apply)
    require(
        'let localPath = stageLocalImagePreview(image, prefix: "local-avatar")'
        in source
        and 'app.applyMyProfileFields(["avatar": localPath])' in source
        and idle < network,
        f"{name} must clear busy immediately after the local avatar appears",
    )

require(
    "var changed = false" in APP
    and "guard changed else { return }" in APP
    and APP.index("guard changed else { return }")
    < APP.index("self.me = me\n        rememberLastUser()", APP.index("func applyMyProfileFields")),
    "unchanged profile fields must not rebuild the whole app state",
)
require(
    "python3 tools/verify-profile-fast-preview.py" in WORKFLOW,
    "profile first-frame responsiveness must run in the iOS gate",
)

print("profile-fast-preview: passed")
