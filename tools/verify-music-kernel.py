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
    "@State private var peerMusic: FriendNowPlaying?" in CHAT
    and "await API.shared.friendsNowPlaying()" in CHAT
    and "MusicPlayer.shared.play(track)" in CHAT
    and "peerMusic.line" in CHAT,
    "direct chats must surface a friend's music state and allow one-tap playback",
)
require(
    "final class MusicPresenceStore" in PRESENCE
    and "struct MusicListeningRing" in PRESENCE
    and "musicOrbit.layer.add(spin" in NATIVE_CHAT
    and "musicListening" in NATIVE_CHAT
    and "MusicListeningRing(size: 46, active: true)" in CHAT,
    "friends who are listening must animate their chat avatars and stop on pause",
)
require(
    "python3 tools/verify-music-kernel.py" in WORKFLOW,
    "music kernel regression must run in the iOS gate",
)

print("music-kernel: passed")
