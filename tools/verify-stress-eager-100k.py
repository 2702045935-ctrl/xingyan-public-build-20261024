#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIG = (ROOT / "Sources" / "StressTestConfiguration.swift").read_text(
    encoding="utf-8"
)
FIXTURE = (ROOT / "Sources" / "MessageStressFixture.swift").read_text(
    encoding="utf-8"
)
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("eager stress verification failed: " + message)


require(
    'environment["XINGYAN_STRESS_EAGER"]' in CONFIG
    and "eagerMessageMaterialization" in CONFIG,
    "stress harness must expose an explicit eager materialisation switch",
)
require(
    'profile == "messages-100000-eager"' in CONFIG
    and "if eagerMessages100K { return true }" in CONFIG
    and "if eagerMessages100K { return false }" in CONFIG,
    "the one-variable 100k eager profile must enable eager materialisation and avoid racing auto-open",
)
require(
    "StressTestConfiguration.eagerMessageMaterialization && all" in FIXTURE
    and "? size" in FIXTURE,
    "eager mode must materialise the complete fixture range rather than one page",
)
require(
    "private var activeInitialMessageWindow: Int" in CHAT
    and "MessageStressFixture.count" in CHAT
    and CHAT.count("activeInitialMessageWindow") >= 6,
    "eager mode must bypass the normal bounded initial window",
)
require(
    "private let initialMessageWindow = 240" in CHAT
    and "private let stressMessageWindow = 1_800" in CHAT
    and "private let historyWindowPages = 10" in CHAT
    and "historyPageSize * historyWindowPages" in CHAT
    and "MessageStressFixture.isActive ? stressMessageWindow : historyWindowLimit" in CHAT
    and "if olderPrefetch.isEmpty, let pending = olderPrefetchTask" in CHAT
    and "private let historyPageSize = 120" in CHAT
    and "let target = historyRunwayTarget" in CHAT
    and "limit: historyPageSize" in CHAT
    and CHAT.count("scheduleOlderPrefetch(before: nextCursor") >= 1,
    "stress and ordinary history must stay inside bounded windows and runways",
)
require(
    "python3 tools/verify-stress-eager-100k.py" in WORKFLOW,
    "eager 100k stress regression must run in the iOS gate",
)

print("stress-eager-100k: passed")
