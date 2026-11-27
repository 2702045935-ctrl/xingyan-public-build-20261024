#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
KERNEL = (ROOT / "Sources" / "SystemMusicKernel.swift").read_text(encoding="utf-8")
PLAYER = (ROOT / "Sources" / "MusicShare.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
PRESENCE = (ROOT / "Sources" / "MusicPresenceStore.swift").read_text(encoding="utf-8")
NATIVE_CHAT = (ROOT / "Sources" / "NativeChatRowCell.swift").read_text(encoding="utf-8")
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
REALTIME = (ROOT / "Sources" / "Realtime.swift").read_text(encoding="utf-8")
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("music kernel verification failed: " + message)


require(
    "AVAudioSession.interruptionNotification" in KERNEL
    and "AVAudioSession.routeChangeNotification" in KERNEL
    and "AVAudioSession.mediaServicesWereResetNotification" in KERNEL
    and "oldDeviceUnavailable" in KERNEL
    and "newDeviceAvailable" in KERNEL,
    "music kernel must recover from interruptions, route changes and media-service resets",
)
require(
    "preferredForwardBuffer" in KERNEL
    and "waitsToMinimizeStalling" in KERNEL
    and "NWPathMonitor" in KERNEL
    and "20_000_000_000" in KERNEL,
    "music kernel must adapt buffering to network and publish a bounded heartbeat",
)
require(
    "CallCenter.shared.$phase" in KERNEL
    and "systemMusicDucking" in KERNEL
    and "systemMusicDucking" in PLAYER,
    "an active call must duck rather than abruptly replace music audio",
)
require(
    "SystemMusicHost" in PLAYER
    and "kernel.attach(self)" in PLAYER
    and "kernel.begin(t)" in PLAYER
    and "kernel.update(position: seconds, duration: total, playing: playing)" in PLAYER
    and "systemMusicPrefetchNext()" in PLAYER
    and "prefetchNextTrack()" in PLAYER,
    "MusicPlayer must use the system kernel and prewarm the next queued track",
)
require(
    '"playing": playing' in API
    and '"position": seconds.isFinite ? max(0, seconds) : 0' in API
    and '"duration": duration.isFinite ? max(0, duration) : 0' in API,
    "now-playing presence must include playback state and progress",
)
require(
    "musicPresence" in SERVER
    and "friendIds(user.id).forEach" in SERVER
    and "playing: it.playing !== false" in SERVER
    and "position: Math.max(0, Number(it.position) || 0)" in SERVER,
    "server presence must fan out to friends and return live position state",
)
require(
    'ev.type == "musicPresence"' in REALTIME
    and ".chrisMusicPresenceChanged" in REALTIME
    and ".chrisMusicPresenceChanged" in PLAYER
    and "friend.liveProgress" in PLAYER,
    "friend music cards must refresh in real time and render live progress",
)
require(
    "final class MusicPresenceStore" in PRESENCE
    and "struct MusicListeningRing" in PRESENCE
    and "musicOrbit.layer.add(spin" in NATIVE_CHAT
    and "musicListening" in NATIVE_CHAT
    and "musicOrbit.isHidden = !listening" in NATIVE_CHAT,
    "friends who are listening must animate their chat avatars and stop on pause",
)
portrait_start = PLAYER.index("private func portraitPlayer")
portrait_end = PLAYER.index("private func landscapePlayer", portrait_start)
portrait = PLAYER[portrait_start:portrait_end]
require(
    "private var lyricTopBar" in PLAYER
    and "private var lyricTrackHeader" in PLAYER
    and "private var lyricSongSwitchGesture" in PLAYER
    and "private func lyricsCard(width: CGFloat, height: CGFloat)" in PLAYER
    and "let cardWidth = max(280, min(380, size.width - 40))" in PLAYER
    and "let cardHeight = min(380, max(320, L.height * 0.398))" in PLAYER
    and "ZStack(alignment: .bottomTrailing)" in PLAYER
    and "MusicGreenCompanion(" in portrait
    and "lyricsViewport" in portrait
    and "artworkPanel" not in portrait
    and "size: 17" in PLAYER
    and "spacing: 15.5" in PLAYER
    and ".padding(.horizontal, 20)" in PLAYER
    and "MusicPlayer.shared.next()" in PLAYER
    and "MusicPlayer.shared.prev()" in PLAYER,
    "music player must use a lyric-first hierarchy with horizontal track switching",
)
require(
    "python3 tools/verify-music-kernel.py" in WORKFLOW,
    "music kernel regression must run in the iOS gate",
)

print("music-kernel: passed")
