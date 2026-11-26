#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
NATIVE = (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat-native-scrollbar verification failed: " + message)


require(
    "virtualHistoryPosition: nil" in CHAT
    and "nativeHistoryPosition" not in CHAT,
    "chat must use the native collection scrollbar",
)
require(
    "collection.showsVerticalScrollIndicator = true" in NATIVE
    and "guard virtualHistoryPosition != nil else { return }" in NATIVE,
    "the fallback virtual thumb must be opt-in for non-chat callers only",
)

print("chat-native-scrollbar: passed")
