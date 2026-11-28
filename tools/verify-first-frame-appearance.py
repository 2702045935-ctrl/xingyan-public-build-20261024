#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")
MAIN_TAB = (ROOT / "Sources" / "MainTab.swift").read_text(encoding="utf-8")
DEFERRED = (ROOT / "Sources" / "ChatDeferred.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
NATIVE_STATIC = (ROOT / "Sources" / "NativeStaticList.swift").read_text(
    encoding="utf-8"
)
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("first-frame appearance failed: " + message)


require(
    "var preferredInterfaceStyle: UIUserInterfaceStyle" in APP
    and "func syncWindowAppearance()" in APP
    and "WindowAppearanceBridge(style: app.preferredInterfaceStyle)" in APP
    and "override func didMoveToWindow()" in APP,
    "the stored appearance must be applied to the owning window before first paint",
)
require(
    "ChatPresentationBackgroundModifier" in MAIN_TAB
    and "presentationBackground(" in MAIN_TAB
    and ".preferredColorScheme(app.preferredScheme)" in MAIN_TAB
    and ".preferredColorScheme(app.preferredScheme)" in DEFERRED
    and ".background(defaultChatCanvasColor().ignoresSafeArea())" in DEFERRED,
    "the full-screen chat cover must own its canvas and appearance on frame zero",
)
require(
    "let dark: Bool?" in NATIVE_STATIC
    and "collection.overrideUserInterfaceStyle = interfaceStyle" in NATIVE_STATIC
    and "dark: scheme == .dark" in CHAT,
    "the native message collection must lock the same appearance as the chat",
)
appear_start = CHATS.index("if !hasInitializedChatCache {")
appear_end = CHATS.index("if MessageStressFixture.autoOpen", appear_start)
chat_first_appear = CHATS[appear_start:appear_end]
require(
    "guard next != cachedChatEntries else { return }" in CHATS
    and "cachedChatEntries = nativeChatEntries(first)" in CHATS
    and "refreshChatListCache(chatSnapshot())" not in chat_first_appear,
    "the chat list must not submit a second table snapshot on first appearance",
)
require(
    "python3 tools/verify-first-frame-appearance.py" in WORKFLOW,
    "first-frame appearance regression must run in the iOS gate",
)

print("first-frame-appearance: passed")
