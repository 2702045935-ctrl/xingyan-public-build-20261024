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
    "@State private var olderPrefetchWaiting = false" in CHAT
    and "olderPrefetchWaiting = olderPrefetch.isEmpty" in CHAT
    and "olderPrefetchWaiting = false" in CHAT
    and "hasher.combine(olderPrefetchWaiting)" in CHAT
    and '"older:\\(hasOlder):\\(olderPrefetchWaiting)"' in CHAT,
    "chat history must show waiting only when no prepared older page exists",
)
require(
    "PrefetchWaitingIndicator(\n"
    "                waiting: olderPrefetchWaiting,\n"
    "                label: Tr(\"正在加载更早消息…\")\n"
    "            )" in CHAT,
    "chat prefetch waiting must use the native circular activity indicator",
)
require(
    "case newerWaiting" in CHAT
    and "native-newer-waiting" in CHAT
    and "newerPrefetchWaiting = newerPrefetch.isEmpty" in CHAT
    and "newerPrefetchWaiting = false" in CHAT
    and "hasher.combine(newerPrefetchWaiting)" in CHAT
    and 'label: Tr("正在加载新消息…")' in CHAT,
    "chat must show waiting only when newer history has no prepared page",
)
require(
    "PrefetchWaitingIndicator(\n"
    "                    waiting: loadingMore,\n"
    "                    label: \"正在加载…\"\n"
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
    and ".accessibilityHidden(!visible)" in INDICATOR,
    "prefetch waiting must use a delayed, animated native system spinner",
)
require(
    "ProgressView()\n"
    "                    .progressViewStyle(.circular)\n"
    "                    .controlSize(.regular)" in MOMENTS
    and "timelineDateLoading" in MOMENTS,
    "Moments date history loading must use the native circular indicator",
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
