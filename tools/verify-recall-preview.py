#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("recall preview verification failed: " + message)


require(
    "if recallSummary(localLast)," in APP
    and "!recallSummary(server.lastMessage)" in APP,
    "same-message server snapshots must not overwrite a local recall summary",
)
require(
    "if recallSummary(localLast), !recallSummary(serverLast)" in APP,
    "optimistic recall summaries must survive until the server catches up",
)
require(
    'Tr("你撤回了一条消息")' in APP
    and 'Tr("对方撤回了一条消息")' in APP
    and 'Tr("撤回了一条消息")' in APP,
    "recall markers must be recognized in every supported locale",
)

print("recall-preview: passed")
