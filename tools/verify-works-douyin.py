#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MISC = (ROOT / "Sources" / "MiscPages.swift").read_text(encoding="utf-8")
FEED = (ROOT / "Sources" / "FeedView.swift").read_text(encoding="utf-8")
ME = (ROOT / "Sources" / "MeView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("works page verification failed: " + message)


require("var createdAt: String?" in FEED,
        "feed items must decode their creation time")
require("struct WorksView: View" in MISC,
        "works profile view must remain in place")
require("private let cols = Array(" in MISC
        and "count: 3" in MISC
        and ".aspectRatio(3.0 / 4.0" in MISC,
        "works must use a three-column portrait cover grid")
require("private var profileCover: String" in MISC
        and "private var coverBanner: some View" in MISC,
        "works profile must have the Douyin-style cover and overlapping avatar")
require(".ignoresSafeArea(edges: .top)" in MISC
        and ".frame(height: 208 + L.safeTop)" in MISC
        and "private var topBar" not in MISC
        and ".swipeBack { dismiss() }" in MISC,
        "works cover must extend behind the status bar with no top button row and left-swipe exit")
require("@State private var showCoverPicker" in MISC
        and "PhotosPicker(limit: 1)" in MISC
        and 'updateMeChecked(["momentCover": url])' in MISC
        and 'Tr("更换背景")' in MISC,
        "works cover must be replaceable from the page and persist through momentCover")
require("let entries: [(String, Int)]" in MISC
        and "pinnedViews: [.sectionHeaders]" in MISC
        and "metric(entry.1)" in MISC,
        "works, likes and private tabs with counts must pin above the cover grid")
require("isPrivate($0)" in MISC and "tag.contains(\"draft\")" in MISC,
        "private and draft works must not leak into the public works tab")
require("mineFromAll" in MISC and "$0.author?.id == myId" in MISC,
        "the works page must recover the signed-in user's posts from the feed")
require("errorState" in MISC and "loadError" in MISC,
        "failed works requests must show a retry state instead of a blank page")
require(
    all(f'Tr("{label}")' in MISC for label in ["作品", "点赞", "互关", "关注", "粉丝"])
    and "socialMetric(metric(social?.works ?? works.count)" in MISC
    and "socialMetric(metric(social?.mutual ?? 0)" in MISC
    and "socialMetric(metric(social?.followers ?? 0)" in MISC
    and "API.shared.feedSocial(" in MISC,
    "works profile must show complete works, likes, mutual, following and follower metrics",
)
require(
    "FeedWorkThumbnail(item: w)" in MISC
    and "MediaTool.firstFrame(url)" in MISC
    and "ImageStore.shared.put(cacheKey, image)" in MISC,
    "works without a generated cover must show and cache the video's first frame",
)
require(".navigationBarTitleDisplayMode(.large)" in ME
        and ".listStyle(.insetGrouped)" in ME,
        "works profile header typography must stay aligned with the native profile page")
require('if item.action == "favorites" { return Tr("备忘录") }' in ME,
        "the Me page entry must be labelled Notes, not Favorites")
require('.navigationTitle(Tr("备忘录"))' in MISC
        and '.confirmationDialog(Tr("添加备忘录")' in MISC,
        "the Notes destination must not fall back to the Favorites title")
require(
    ".swipeActions(edge: .leading, allowsFullSwipe: false)" in MISC
    and ".swipeActions(edge: .trailing, allowsFullSwipe: true)" in MISC
    and '.tint(.orange)' in MISC
    and 'Label(Tr("删除"), systemImage: "trash.fill")' in MISC,
    "Notes rows must use Apple Notes gestures: swipe right to pin and swipe left to delete",
)
print("works-douyin: passed")
