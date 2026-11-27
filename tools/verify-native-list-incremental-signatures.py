#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LIST = (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("native list incremental signature verification failed: " + message)


require("let isPureAppend = !order.isEmpty" in LIST,
        "tail appends must avoid full prepend scans")
require(
    "nextSignatures = Dictionary(uniqueKeysWithValues: next.map {" not in LIST,
    "scrolling updates must not regenerate every row signature",
)
require(
    "old == item" in LIST and "let existing = signatures[item.id]" in LIST,
    "only new or changed rows may rebuild their signature",
)
require(
    "if nextOrder == order && nextSignatures == signatures" in LIST,
    "unchanged scroll frames must return before diff bookkeeping",
)
cell_start = LIST.index("private final class NativeStaticHostCell")
cell_end = LIST.index("final class NativeStaticListController", cell_start)
cell = LIST[cell_start:cell_end]
require(
    "contentConfiguration = UIHostingConfiguration { rootView }" in cell
    and ".margins(.all, 0)" in cell
    and ".background(.clear)" in cell
    and "UIHostingController<AnyView>" not in cell
    and "addSubview(" not in cell,
    "native list cells must use system hosting configuration without a manual host lifecycle",
)

print("native-list-incremental-signatures: passed")
