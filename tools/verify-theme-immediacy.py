#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")
SIDEBAR = (ROOT / "Sources" / "AccountSidebarView.swift").read_text(encoding="utf-8")
ACCOUNTS = (ROOT / "Sources" / "SwitchAccountView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("theme immediacy verification failed: " + message)


start = APP.index("func setAppearance(_ v: String)")
end = APP.index("func withSoftChatTransition", start)
theme_switch = APP[start:end]
require(
    "appearance = v\n"
    "        UserDefaults.standard.set(v, forKey: \"chris.appearance\")\n"
    "        appearanceVeilOpacity = 0" in theme_switch
    and "Task.sleep(nanoseconds: 150_000_000)" not in theme_switch
    and "self.appearance = v" not in theme_switch,
    "appearance state must commit immediately without a timed pre-switch delay",
)
require(
    ".systemAnimation(.easeInOut(duration: 0.38), value: app.appearance)" not in APP,
    "the root view must not interpolate every surface during a theme switch",
)
require(
    "@Environment(\\.colorScheme) private var scheme" in SIDEBAR
    and "Color.dyn(" in SIDEBAR
    and "@Environment(\\.colorScheme) private var scheme" in ACCOUNTS
    and "private var pageBackground: Color" in ACCOUNTS,
    "account surfaces must resolve semantic colors from the current scheme",
)
require(
    "python3 tools/verify-theme-immediacy.py" in WORKFLOW,
    "theme immediacy regression must run in the iOS gate",
)

print("theme-immediacy: passed")
