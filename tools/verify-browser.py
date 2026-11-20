#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BROWSER = (ROOT / "Sources" / "InAppBrowser.swift").read_text(
    encoding="utf-8"
)
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("browser verification failed: " + message)


require(
    "import WebKit" in BROWSER
    and "WKWebView(frame: .zero, configuration: config)" in BROWSER
    and "allowsBackForwardNavigationGestures = true" in BROWSER
    and "performDefaultHandling" in BROWSER
    and "ServerTrustPolicy.canAccept" not in BROWSER,
    "browser must use WebKit with normal system certificate handling",
)
require(
    "ExternalLinkRouter" not in BROWSER
    and "schemes are cancelled" in BROWSER.lower()
    and "removeData" not in BROWSER,
    "WEB links must stay in the persistent in-app WebKit session",
)
require(
    "struct InAppBrowserView" in BROWSER
    and "private struct BrowserTab" in BROWSER
    and "BrowserTabsSheet" in BROWSER
    and "nonPersistent()" in BROWSER
    and "onNewWindow" in BROWSER,
    "browser must provide tabs and isolated private browsing",
)
require(
    "BrowserDataStore" in BROWSER
    and "record(url: URL" in BROWSER
    and "toggleBookmark" in BROWSER
    and "BrowserHistorySheet" in BROWSER
    and "BrowserBookmarksSheet" in BROWSER,
    "browser must persist history and bookmarks",
)
require(
    "WKFindConfiguration" in BROWSER
    and "func reader(" in BROWSER
    and "BrowserReaderSheet" in BROWSER
    and "customUserAgent" in BROWSER,
    "browser must provide find-in-page, reader mode and desktop mode",
)
require(
    "python3 tools/verify-browser.py" in WORKFLOW,
    "browser regression must run in the iOS gate",
)

print("browser: passed")
