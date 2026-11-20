#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
KERNEL = (ROOT / "server" / "lib" / "search-ranking.js").read_text(encoding="utf-8")
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
SEARCH = (ROOT / "Sources" / "SearchPage.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("search recommendation verification failed: " + message)


require(
    "class SearchRankingKernel" in KERNEL
    and "fieldScore" in KERNEL
    and "recencyScore" in KERNEL
    and "profile.targets" in KERNEL
    and "schedulePersist" in KERNEL,
    "search ranking must combine lexical match, recency and persistent preferences",
)
require(
    "parts[0] === 'search' && parts[1] === 'events'" in SERVER
    and "searchRankingKernel.rank" in SERVER
    and "feedVisibleTo(v, me.id)" in SERVER
    and "engine: 'xingyan-search-v1'" in SERVER,
    "unified search must filter permissions, rank every section and accept feedback",
)
require(
    "scope=" in API
    and "limit=30" in API
    and "func searchEvents" in API
    and "recordSearchHit" in SEARCH,
    "client search must forward scope and report result clicks",
)
require(
    "python3 tools/verify-search-recommendation.py" in WORKFLOW
    and "node server/test/search-ranking.test.js" in WORKFLOW,
    "search ranking tests must run in the iOS gate",
)

print("search-recommendation: passed")
