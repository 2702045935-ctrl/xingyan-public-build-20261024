#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
VIEW = (ROOT / "Sources" / "DiscoverView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("moment own publish verification failed: " + message)


require(
    "MomentCreatePayload" in API
    and "async throws -> Moment?" in API
    and "return (try? decode(raw, as: MomentCreatePayload.self))?.moment" in API,
    "posting must return the canonical created moment",
)
require(
    "locallyPostedMoments" in VIEW
    and "insertLocallyPostedMoment(created)" in VIEW,
    "a successful publish must enter the visible feed immediately",
)
require(
    'API.shared.updateMeChecked(["momentCover": url])' in VIEW
    and "app.applyMyProfileUser(updated)" in VIEW
    and "setCoverOverride(url)" in VIEW.split(
        'API.shared.updateMeChecked(["momentCover": url])', 1
    )[1].split("} else {", 1)[0],
    "a saved Moments cover must remain visible without leaving the page",
)
require(
    "RemoteImage(path: cover, icon: \"photo\", maxSide: 2560)" in VIEW
    and ".id(cover)" not in VIEW,
    "cover replacement must not recreate the image view and expose a blank frame",
)
require(
    "pendingLocal + cleanPage.filter" in VIEW,
    "a stale server page must not erase a just-published moment",
)
require(
    "publishError" in VIEW
    and "Text(publishError)" in VIEW
    and "publishError = message" in VIEW,
    "publish failures must stay visible and must not silently clear the draft",
)
require(
    "var uploadError: String?" in VIEW
    and "while nextIdx < min(3, picked.count)" in VIEW
    and "if let uploadError {\n                throw APIError.message(uploadError)" in VIEW
    and "guard mResults.count == picked.count else" in VIEW
    and "图片上传不完整，请重试" in VIEW
    and "let up = try? await API.shared.uploadImageForSend(" not in VIEW,
    "Moments must fail visibly instead of publishing a text-only post when an image upload fails",
)

CARD = (ROOT / "Sources" / "MomentFeedCard.swift").read_text(encoding="utf-8")
require(
    "HStack(spacing: -7)" in CARD
    and "stroke(socialSurface, lineWidth: 2)" in CARD,
    "liked-user avatars must overlap as one connected stack",
)

SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
require(
    "async function ensureMomentFriendIndex" in SERVER
    and "syncFriendshipCacheFromOwners([userId], 650)" in SERVER
    and "await ensureMomentFriendIndex(user.id);" in SERVER,
    "Moments reads must refresh friends from shard owners before visibility filtering",
)
require(
    "/__shard/moment-replicate" in SERVER
    and "moment-replication-outbox.json" in SERVER
    and "JSON.stringify({ op: 'delete', id })" in SERVER
    and "primeMomentReplicationState();" in SERVER,
    "moment publishes and tombstones must replicate durably across shards",
)
require(
    "let mergedPage = applyNewestMomentPage(feed.moments)" in VIEW
    and "LocalStore.saveMoments(mergedPage" in VIEW
    and "forgetMomentLocally(event.momentId)" in VIEW,
    "deleted moments must disappear from live state and the local cache immediately",
)
require(
    "guard !list.isEmpty else" in (
        ROOT / "Sources" / "LocalStore.swift"
    ).read_text(encoding="utf-8"),
    "an empty confirmed feed must clear the stale local Moments cache",
)

print("moment-own-publish: passed")
