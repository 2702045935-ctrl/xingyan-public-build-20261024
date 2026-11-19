#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NEWS = (ROOT / "Sources" / "NewsView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("compact news verification failed: " + message)


require(
    "if compact {\n                compactFeed" in NEWS
    and "private var compactFeed: some View" in NEWS,
    "compact chat news must use a continuous feed instead of the premium page",
)
require(
    "private var compactTopics: [NewsTopic]" in NEWS
    and "start + 4" in NEWS
    and "compactArticleRow" in NEWS,
    "compact news topics must group three to four small message-like rows",
)
require(
    "private func loadCompactMore() async" in NEWS
    and ".onAppear {" in NEWS
    and "loadCompactMore" in NEWS,
    "compact news must prefetch the next batch when the user approaches the end",
)
require(
    "python3 tools/verify-news-compact-scroll.py" in WORKFLOW,
    "compact news scroll regression must run in the iOS gate",
)

print("news-compact-scroll: passed")
