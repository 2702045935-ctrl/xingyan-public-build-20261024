#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")
SIDEBAR = (ROOT / "Sources" / "AccountSidebarView.swift").read_text(encoding="utf-8")
ACCOUNTS = (ROOT / "Sources" / "SwitchAccountView.swift").read_text(encoding="utf-8")
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
NATIVE_LIST = (ROOT / "Sources" / "NativeChatList.swift").read_text(encoding="utf-8")
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
    "window.overrideUserInterfaceStyle = windowStyle" in theme_switch
    and "for case let scene as UIWindowScene in UIApplication.shared.connectedScenes"
    in theme_switch,
    "the owning windows must adopt an explicit appearance in the same update",
)
require(
    ".systemAnimation(.easeInOut(duration: 0.38), value: app.appearance)" not in APP,
    "the root view must not interpolate every surface during a theme switch",
)
require(
    "scheme == .dark || app.appearance == \"dark\"" not in CHATS
    and "switch app.appearance" in CHATS
    and "UIConfig.fixedLight(\"chatsPageBg\", 0xF5F5F5)" in CHATS,
    "explicit conversation appearance must take priority over delayed environment updates",
)
require(
    "table.overrideUserInterfaceStyle = dark ? .dark : .light" in NATIVE_LIST
    and "controller.tableView.overrideUserInterfaceStyle = dark ? .dark : .light"
    in NATIVE_LIST
    and "UIView.performWithoutAnimation" in NATIVE_LIST,
    "the native chats table must repaint visible rows without an implicit animation",
)
require(
    "@Environment(\\.colorScheme) private var scheme" in SIDEBAR
    and "Color.dyn(" in SIDEBAR
    and "Color(uiColor: .systemGroupedBackground)" in ACCOUNTS
    and ".scrollContentBackground(.hidden)" in ACCOUNTS,
    "account surfaces must resolve through system semantic colors",
)
require(
    "python3 tools/verify-theme-immediacy.py" in WORKFLOW,
    "theme immediacy regression must run in the iOS gate",
)

print("theme-immediacy: passed")
