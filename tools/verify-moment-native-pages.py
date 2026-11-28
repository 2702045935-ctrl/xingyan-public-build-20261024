#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DISCOVER = (ROOT / "Sources" / "DiscoverView.swift").read_text(encoding="utf-8")
COMMENTS = (ROOT / "Sources" / "MomentCommentsSheet.swift").read_text(encoding="utf-8")
LIKES = (ROOT / "Sources" / "MomentLikesViews.swift").read_text(encoding="utf-8")
NOTICES = (ROOT / "Sources" / "MomentNoticesView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("moment native pages verification failed: " + message)


group_start = DISCOVER.index("struct MomentGroupPage: View")
group = DISCOVER[group_start:DISCOVER.index("struct CoverAdjustSheet: View", group_start)]
require(
    "NativeMomentFeed(" in group
    and "ScrollView {" not in group
    and "LazyVStack" not in group
    and "MomentRow(" not in group,
    "the moment group page must use the native feed with no SwiftUI list fallback",
)
require(
    "struct MomentRow" not in DISCOVER
    and "struct MomentImageGrid" not in DISCOVER
    and "struct MomentSingleImage" not in DISCOVER,
    "legacy SwiftUI moment row and media grids must be removed",
)
require(
    "NativeStaticList(" in COMMENTS
    and "MomentCommentNativeItem" in COMMENTS
    and "commentListController.scrollToID(" in COMMENTS
    and "LazyVStack" not in COMMENTS,
    "moment comments must use one native list for context, comments and bottom inset",
)
require(
    "NativeStaticList(" in LIKES
    and "MomentLikeNativeItem" in LIKES
    and "ScrollView {" not in LIKES
    and "LazyVStack" not in LIKES,
    "moment likes must use a native reusable list",
)
require(
    "NativeStaticList(" in NOTICES
    and "MomentNoticeNativeItem" in NOTICES
    and "ScrollView {" not in NOTICES
    and "LazyVStack" not in NOTICES,
    "moment notices must use a native reusable list",
)
require(
    "python3 tools/verify-moment-native-pages.py" in WORKFLOW,
    "native moment subpage regression must run in the iOS gate",
)

print("moment-native-pages: passed")
