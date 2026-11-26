#!/usr/bin/env python3
"""Exercise the two-way chat history window without touching the UI."""

from __future__ import annotations

import random


PAGE_SIZE = 120
WINDOW_PAGES = 10
RUNWAY_PAGES = 3
WINDOW_LIMIT = PAGE_SIZE * WINDOW_PAGES
RUNWAY_LIMIT = PAGE_SIZE * RUNWAY_PAGES


class Server:
    def __init__(self, total: int) -> None:
        self.total = total

    def before(self, cursor: int) -> tuple[list[int], bool]:
        upper = min(self.total, max(0, cursor - 1))
        start = max(1, upper - PAGE_SIZE + 1)
        if start > upper:
            return [], False
        return list(range(start, upper + 1)), start > 1

    def since(self, cursor: int) -> tuple[list[int], bool]:
        start = max(1, cursor + 1)
        end = min(self.total, start + PAGE_SIZE - 1)
        if start > end:
            return [], False
        return list(range(start, end + 1)), end < self.total


class Window:
    def __init__(self, server: Server, initial: int = 240) -> None:
        self.server = server
        self.items = list(range(max(1, server.total - initial + 1), server.total + 1))
        self.older: list[int] = []
        self.newer: list[int] = []
        self.older_more = False
        self.newer_more = False

    @property
    def oldest(self) -> int:
        return self.items[0]

    @property
    def newest(self) -> int:
        return self.items[-1]

    def prefetch_older(self) -> None:
        if len(self.older) >= RUNWAY_LIMIT or not self.older_more and self.older:
            return
        known = set(self.items).union(self.older)
        cursor = self.oldest
        while len(self.older) < RUNWAY_LIMIT:
            rows, more = self.server.before(cursor)
            if not rows:
                self.older_more = False
                break
            known.update(rows)
            self.older = sorted(known.difference(self.items))
            self.older_more = more
            cursor = min(rows)
            if not more:
                break
        if not self.older:
            self.older_more = False

    def prefetch_newer(self) -> None:
        if len(self.newer) >= RUNWAY_LIMIT or not self.newer_more and self.newer:
            return
        known = set(self.items).union(self.newer)
        cursor = self.newest
        while len(self.newer) < RUNWAY_LIMIT:
            rows, more = self.server.since(cursor)
            if not rows:
                self.newer_more = False
                break
            known.update(rows)
            self.newer = sorted(
                value for value in known if value > self.newest
            )
            self.newer_more = more
            cursor = max(rows)
            if not more:
                break
        if not self.newer:
            self.newer_more = False

    def consume_older(self) -> bool:
        self.prefetch_older()
        if not self.older:
            return False
        incoming = self.older[-PAGE_SIZE:]
        self.older = self.older[:-PAGE_SIZE]
        merged = sorted(set(self.items).union(incoming))
        self.items = merged[:WINDOW_LIMIT]
        self.newer = []
        self.newer_more = False
        self.prefetch_older()
        self.prefetch_newer()
        return True

    def consume_newer(self) -> bool:
        self.prefetch_newer()
        if not self.newer:
            return False
        incoming = self.newer[:PAGE_SIZE]
        self.newer = self.newer[PAGE_SIZE:]
        merged = sorted(set(self.items).union(incoming))
        self.items = merged[-WINDOW_LIMIT:]
        self.older = []
        self.older_more = False
        self.prefetch_newer()
        self.prefetch_older()
        return True


def assert_invariants(window: Window) -> None:
    values = window.items
    if not values or len(values) > WINDOW_LIMIT:
        raise AssertionError(f"window size invalid: {len(values)}")
    if values != list(range(values[0], values[-1] + 1)):
        raise AssertionError("active history window is not contiguous")
    if window.older and window.older[-1] >= values[0]:
        raise AssertionError("older runway overlaps the active window")
    if window.newer and window.newer[0] <= values[-1]:
        raise AssertionError("newer runway overlaps the active window")


def main() -> None:
    total = 300_000
    window = Window(Server(total))
    seen = set(window.items)
    for _ in range(total // PAGE_SIZE + 200):
        if not window.consume_older():
            break
        seen.update(window.items)
        assert_invariants(window)
    if window.oldest != 1:
        raise AssertionError(f"older traversal stopped at {window.oldest}")
    if len(seen) != total:
        raise AssertionError(f"older traversal lost {total - len(seen)} rows")

    for _ in range(total // PAGE_SIZE + 200):
        if not window.consume_newer():
            break
        seen.update(window.items)
        assert_invariants(window)
    if window.newest != total:
        raise AssertionError(f"newer traversal stopped at {window.newest}")
    if len(seen) != total:
        raise AssertionError(f"round trip lost {total - len(seen)} rows")

    random.seed(42)
    for _ in range(100_000):
        if random.random() < 0.5:
            window.consume_older()
        else:
            window.consume_newer()
        assert_invariants(window)

    print(
        "chat-windowed-history-model: passed",
        {
            "rows": total,
            "windowLimit": WINDOW_LIMIT,
            "runwayLimit": RUNWAY_LIMIT,
            "randomOperations": 100_000,
        },
    )


if __name__ == "__main__":
    main()
