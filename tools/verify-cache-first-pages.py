#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")
GAMES = (ROOT / "Sources" / "GamesPageView.swift").read_text(encoding="utf-8")
MUSIC = (ROOT / "Sources" / "MusicShare.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("cache-first page verification failed: " + message)


require(
    "func cachedMusicTracks() -> [MusicTrack]" in API
    and "func cachedMiniApps(kind: String = \"\") -> [MiniApp]" in API,
    "catalog pages must expose a synchronous account-scoped disk snapshot",
)
require(
    '@State private var games: [MiniApp] = API.shared.cachedMiniApps(kind: "game")'
    in GAMES
    and '@State private var loading = API.shared.cachedMiniApps(kind: "game").isEmpty'
    in GAMES
    and "if loading && list.isEmpty" in GAMES,
    "the games page must render cached games before refreshing the network",
)
require(
    "let cachedIndex = root.appendingPathComponent(\"index.html\")" in GAMES
    and "localIndex = cachedIndex\n                loading = false" in GAMES,
    "a cached game must become visible before its asset manifest refresh",
)
require(
    "@State private var tracks: [MusicTrack] = API.shared.cachedMusicTracks()"
    in MUSIC
    and "@State private var loading = API.shared.cachedMusicTracks().isEmpty"
    in MUSIC,
    "the music page must render its cached library before refreshing the network",
)
require(
    "contacts = Self.cachedContacts(userId: cached.id)" in APP
    and "Self.saveCachedContacts(friends, userId: me?.id)" in APP
    and APP.count("Self.saveCachedContacts(friends, userId: me?.id)") >= 2,
    "contacts must be available on the first frame and refreshed in the background",
)

print("cache-first-pages: passed")
