#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SEARCH = (ROOT / "Sources" / "SearchAllView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("global search verification failed: " + message)


require(
    "private struct SearchScopePressStyle" in SEARCH
    and "buttonStyle(SearchScopePressStyle())" in SEARCH
    and ".buttonStyle(MenuPressStyle())" in SEARCH,
    "search scopes and result rows need the shared restrained press feedback",
)
require(
    "@State private var searchFailed = false" in SEARCH
    and 'Text(Tr("搜索暂时不可用"))' in SEARCH
    and 'Button(Tr("重新搜索"))' in SEARCH
    and 'Text(Tr("结果可能没有更新"))' in SEARCH,
    "search must distinguish network failure from an empty result",
)
require(
    "if searching && data == nil" in SEARCH
    and "if searching {\n                            ProgressView()" in SEARCH,
    "search must keep previous results during refresh instead of flashing",
)
require(
    "private func openMessage(_ hit: SearchAllData.ChatHit)" in SEARCH
    and "ChatSearchJump.request(chatId: hit.chatId" in SEARCH,
    "message search results must jump to the matched message",
)
require(
    "(\"moments\", \"生活圈\")" in SEARCH,
    "the search scope must use the app's Life Circle terminology",
)
require(
    "python3 tools/verify-search-all.py" in WORKFLOW,
    "global search regression must run in the iOS gate",
)

print("search-all: passed")
