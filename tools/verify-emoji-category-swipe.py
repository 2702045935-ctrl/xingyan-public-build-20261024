#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PANELS = (ROOT / "Sources" / "Panels.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("emoji category swipe verification failed: " + message)


require("TabView(selection: $tab)" in PANELS
        and ".tabViewStyle(.page(indexDisplayMode: .never))" in PANELS,
        "emoji pages must remain horizontally swipable")
require("ScrollViewReader { tabProxy in" in PANELS
        and "tabProxy.scrollTo(value, anchor: .center)" in PANELS
        and ".id(singleTabIndex)" in PANELS,
        "the category strip must follow the selected page and scroll horizontally")

print("emoji-category-swipe: passed")
