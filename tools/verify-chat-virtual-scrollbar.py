#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
NATIVE = (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat-native-scrollbar verification failed: " + message)


require(
    "virtualHistoryPosition" not in CHAT
    and "nativeHistoryPosition" not in CHAT
    and "collection.showsVerticalScrollIndicator = true" in NATIVE
    and "collection.isDirectionalLockEnabled = true" in NATIVE,
    "chat must use the native collection scroll indicator without a custom thumb",
)

print("chat-native-scrollbar: passed")
