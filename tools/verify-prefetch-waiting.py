#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
MOMENTS = (ROOT / "Sources" / "DiscoverView.swift").read_text(encoding="utf-8")
INDICATOR = (ROOT / "Sources" / "PrefetchWaitingIndicator.swift").read_text(
    encoding="utf-8"
)
CONTACTS = (ROOT / "Sources" / "ContactsView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("prefetch waiting verification failed: " + message)


require(
    "private var olderPrefetchWaitingVisible: Bool" in CHAT
    and "loadingOlder && olderPrefetch.isEmpty" in CHAT
    and '"older:\\(hasOlder):\\(olderPrefetchWaitingVisible)"' in CHAT,
    "chat prefetch must stay silent until a boundary request has no prepared page",
)
require(
    "PrefetchWaitingIndicator(\n"
    "                waiting: olderPrefetchWaitingVisible,\n"
    "                label: Tr(\"正在加载更早消息…\")\n"
    "            )" in CHAT
    and ".frame(height: 44)" in CHAT,
    "chat prefetch waiting must use the native circular activity indicator",
)
require(
    "PrefetchWaitingIndicator(\n"
    "                    waiting: loadingMore,\n"
    "                    label: Tr(\"正在加载…\")\n"
    "                )" in MOMENTS
    and ".frame(height: 49)" in MOMENTS,
    "Moments waiting must use the native indicator and hold footer height",
)
require(
    "ProgressView()\n"
    "                .progressViewStyle(.circular)\n"
    "                .controlSize(.small)" in INDICATOR
    and "Task.sleep(nanoseconds: 180_000_000)" in INDICATOR
    and ".animation(.easeOut(duration: 0.16), value: visible)" in INDICATOR
    and ".font(.footnote)" in INDICATOR
    and ".accessibilityHidden(!visible)" in INDICATOR,
    "prefetch waiting must use a delayed, animated native system spinner",
)
require(
    "@State private var initialLoading = false" in CONTACTS
    and "initialLoading = app.contacts.isEmpty" in CONTACTS
    and "initialLoading = false" in CONTACTS
    and "PrefetchWaitingIndicator(\n"
    "                                        waiting: true,\n"
    "                                        label: Tr(\"正在加载联系人…\")\n"
    "                                    )" in CONTACTS,
    "contacts must show a native waiter only for a first load with no cache",
)
require(
    "python3 tools/verify-prefetch-waiting.py" in WORKFLOW,
    "prefetch waiting regression must run in the iOS gate",
)

print("prefetch-waiting: passed")
