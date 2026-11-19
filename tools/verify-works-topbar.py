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
    and "topBar\n                .padding(.top, L.safeTop)" in WORKS,
    "works page must use one full-screen coordinate space for cover and top bar",
)
require(
    WORKS.count(".ignoresSafeArea(edges: .top)") >= 3,
    "scroll content, page background and root container must share the top safe-area policy",
)
require(
    "Button { dismiss() }" in WORKS
    and 'Text(Tr("我的作品"))' in WORKS
    and "Menu {" in WORKS,
    "works page must keep back, centered title and right-side actions in the fixed top bar",
)
require(
    "python3 tools/verify-works-topbar.py" in WORKFLOW,
    "works top-bar layout regression must run in the iOS gate",
)

print("works-topbar: passed")
