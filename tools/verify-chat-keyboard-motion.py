#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat keyboard motion verification failed: " + message)


require(
    ".safeAreaInset(edge: .bottom, spacing: 0)" in CHAT
    and "KeyboardLiftDisable" not in CHAT
    and "chatKeyboardManual" not in CHAT
    and "kbHeight" not in CHAT
    and ".ignoresSafeArea(.keyboard, edges: .bottom)" not in CHAT,
    "chat must use the system keyboard safe-area animation",
)
require(
    CHAT.count("keyboardWillChangeFrameNotification") == 1
    and "keyboardDidShowNotification" not in CHAT
    and "private func followKeyboardBottom(_ notice: Notification)" in CHAT
    and "pinTask?.cancel()" in CHAT
    and "await Task.yield()" in CHAT
    and "UIView.animate(" in CHAT
    and ".beginFromCurrentState" in CHAT
    and ".allowUserInteraction" in CHAT
    and "nativeMessageController.scrollToBottom(animated: false)" in CHAT,
    "one keyboard transition must follow the native list bottom with the system curve",
)
require(
    "python3 tools/verify-chat-keyboard-motion.py" in WORKFLOW,
    "keyboard motion regression must run in the iOS gate",
)

print("chat-keyboard-motion: passed")
