#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
POP = (ROOT / "Sources" / "NativeInteractivePop.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
KERNEL = (ROOT / "Sources" / "InteractionKernel.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("interaction kernel verification failed: " + message)


require(
    "interactivePopGestureRecognizer" in POP
    and "navigation.viewControllers.count > 1" in POP,
    "hidden navigation-bar screens must use UIKit interactive pop with root protection",
)
require(
    "NativeInteractivePopEnabler" in CHAT
    and ".swipeBack { dismiss() }" not in CHAT,
    "chat must use the native pop gesture instead of a custom swipe-back transform",
)
require(
    "InteractionKernel.shared.begin(page: \"chat\"" in CHATS
    and "InteractionKernel.shared.complete(page: \"chat\"" in CHAT,
    "chat handoff timing must cover source tap through destination appearance",
)
require(
    "pagePush" in KERNEL and "pagePop" in KERNEL and "interruptionSpring" in KERNEL,
    "page transitions must share one motion budget",
)
require(
    "python3 tools/verify-interaction-kernel.py" in WORKFLOW,
    "interaction handoff regression must run in the iOS gate",
)

print("interaction-kernel: passed")
