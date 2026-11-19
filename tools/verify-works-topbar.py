#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PAGES = (ROOT / "Sources" / "MiscPages.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)
WORKS = PAGES.split("struct WorksView: View", 1)[1].split(
    "struct ", 1
)[0]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("works top bar verification failed: " + message)


require(
    "ScrollView {" in WORKS
    and ".ignoresSafeArea(edges: .top)" in WORKS
    and "private var topBar" not in WORKS
    and ".swipeBack { dismiss() }" in WORKS,
    "works page must stay full screen without a top button row and keep left-swipe exit",
)
require(
    WORKS.count(".ignoresSafeArea(edges: .top)") >= 2,
    "scroll content and the page background must share the top safe-area policy",
)
require(
    "coverBanner" in WORKS
    and 'Tr("更换背景")' in WORKS
    and "private var tabs" in WORKS,
    "works actions must live in the cover and content instead of a fixed top bar",
)
require(
    "python3 tools/verify-works-topbar.py" in WORKFLOW,
    "works top-bar layout regression must run in the iOS gate",
)

print("works-topbar: passed")
