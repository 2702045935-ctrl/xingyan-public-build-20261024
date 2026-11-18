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
    "pendingLocal + cleanPage.filter" in VIEW,
    "a stale server page must not erase a just-published moment",
)
require(
    "publishError" in VIEW
    and "Text(publishError)" in VIEW
    and "publishError = message" in VIEW,
    "publish failures must stay visible and must not silently clear the draft",
)

CARD = (ROOT / "Sources" / "MomentFeedCard.swift").read_text(encoding="utf-8")
require(
    "HStack(spacing: -7)" in CARD
    and "stroke(socialSurface, lineWidth: 2)" in CARD,
    "liked-user avatars must overlap as one connected stack",
)

print("moment-own-publish: passed")
