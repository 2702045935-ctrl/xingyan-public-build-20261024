#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FEED = (ROOT / "Sources" / "FeedView.swift").read_text(encoding="utf-8")
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("video publish verification failed: " + message)


require(
    ".fullScreenCover(isPresented: $showPublish)" in FEED
    and "private var publishEditor: some View" in FEED
    and "private var publishSheet" not in FEED,
    "publishing must use the new full-screen editor instead of the legacy form sheet",
)
require(
    "publishPreview(height:" in FEED
    and "publishDescriptionCard" in FEED
    and "publishSettingsCard" in FEED
    and "publishQuickToken(\"#\")" in FEED,
    "the Douyin editor needs immersive preview, caption tools and grouped publishing settings",
)
require(
    "coverPickOpen = true" in FEED
    and "API.shared.uploadCover(image: cover)" in FEED
    and "cover: coverPath" in FEED,
    "custom cover selection must upload and persist with the work",
)
require(
    'Button(Tr("公开")) { publishVisibility = "public" }' in FEED
    and 'Button(Tr("仅朋友")) { publishVisibility = "friends" }' in FEED
    and 'Button(Tr("仅自己")) { publishVisibility = "private" }' in FEED
    and "visibility === 'friends'" in SERVER
    and "['friends', 'private', 'partial', 'exclude']" in SERVER,
    "audience selection must be enforced by the server",
)
require(
    'func feedPublish(video: String, desc: String, music: String, cover: String = ""' in API,
    "the API must carry the selected cover into the published work",
)
require(
    "python3 tools/verify-video-publish-douyin.py" in WORKFLOW,
    "the full-screen publishing regression must run in the iOS gate",
)

print("video-publish-douyin: passed")
