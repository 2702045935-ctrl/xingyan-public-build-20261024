#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAIN = (ROOT / "Sources" / "MainTab.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("tab first-frame verification failed: " + message)


require(
    "private func selectTab(_ next: Int)" in MAIN
    and "mountedTabs.insert(next)" in MAIN
    and "guard tab != next else { return }" in MAIN
    and "withTransaction(transaction)" in MAIN
    and "transaction.disablesAnimations = true" in MAIN,
    "the destination tab must be mounted before selection is published",
)
require(
    "NativeTabBar(selection: Binding(\n"
    "                                 get: { tab },\n"
    "                                 set: { selectTab($0) })" in MAIN,
    "the native tab bar must use the atomic mount-and-select path",
)
require(
    MAIN.count("selectTab(") >= 5
    and "\n                tab = 0" not in MAIN
    and "if v { tab = 0;" not in MAIN,
    "programmatic tab changes must not bypass the atomic mount path",
)

print("tab-first-frame: passed")
