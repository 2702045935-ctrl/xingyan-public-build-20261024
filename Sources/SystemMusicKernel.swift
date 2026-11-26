import AVFoundation
import Combine
import Foundation
import Network
import UIKit
import MusicModule

typealias MusicKernelState = MusicPlaybackState

extension Notification.Name {
    static let chrisMusicPresenceChanged =
        Notification.Name("chris.music.presence-changed")
}

@MainActor
protocol SystemMusicHost: AnyObject {
    var systemMusicIsPlaying: Bool { get }
    var systemMusicPosition: Double { get }
    func systemMusicPauseForInterruption()
    func systemMusicResume()
    func systemMusicRecover(at position: Double)
    func systemMusicPrefetchNext()
    func systemMusicDucking(_ active: Bool)
}

@MainActor
final class SystemMusicKernel: ObservableObject {
    static let shared = SystemMusicKernel()

    @Published private(set) var state: MusicKernelState = .idle
    @Published private(set) var networkConstrained = false
    @Published private(set) var networkExpensive = false

    private weak var host: SystemMusicHost?
    private var started = false
    private var currentTrack: MusicTrack?
    private var position: Double = 0
    private var duration: Double = 0
    private var playing = false
    private var userPaused = true
    private var resumeAfterInterruption = false
    private var routePaused = false
    private var lastReportAt = Date.distantPast
    private var heartbeatTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var callCancellable: AnyCancellable?
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "chris.music.network")

    private init() {}

    func attach(_ host: SystemMusicHost) {
        self.host = host
        startIfNeeded()
    }

    var preferredForwardBuffer: Double {
        playbackPolicy.preferredForwardBuffer
    }

    var waitsToMinimizeStalling: Bool {
        playbackPolicy.waitsToMinimizeStalling
    }

    private var playbackPolicy: MusicPlaybackPolicy {
        MusicPlaybackPolicy(networkConstrained: networkConstrained,
                            networkExpensive: networkExpensive)
    }

    @discardableResult
    func activateSession() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            try session.setActive(true)
            return true
        } catch {
            CrashCatcher.note("音乐内核", "音频会话激活失败 \(error.localizedDescription)")
            return false
        }
    }

    func begin(_ track: MusicTrack) {
        startIfNeeded()
        currentTrack = track
        position = 0
        duration = 0
        playing = true
        userPaused = false
        resumeAfterInterruption = false
        routePaused = false
        state = .playing
        _ = activateSession()
        report(force: true)
        startHeartbeat()
        host?.systemMusicPrefetchNext()
    }

    func update(position: Double, duration: Double, playing: Bool, force: Bool = false) {
        if position.isFinite { self.position = max(0, position) }
        if duration.isFinite, duration > 0 { self.duration = duration }
        self.playing = playing
        if state != .interrupted, state != .recovering, currentTrack != nil {
            state = playing ? .playing : (userPaused ? .paused : state)
        }
        report(force: force)
    }

    func pause(userInitiated: Bool) {
        playing = false
        if userInitiated {
            userPaused = true
            resumeAfterInterruption = false
            state = .paused
            report(force: true)
            stopHeartbeat()
        }
    }

    func resume() {
        userPaused = false
        resumeAfterInterruption = false
        routePaused = false
        playing = true
        state = .playing
        _ = activateSession()
        report(force: true)
        startHeartbeat()
    }

    func seek() {
        report(force: true)
    }

    func stop() {
        currentTrack = nil
        position = 0
        duration = 0
        playing = false
        userPaused = true
        state = .idle
        stopHeartbeat()
        report(force: true)
    }

    func finish() {
        position = duration
        playing = false
        report(force: true)
    }

    func queueChanged() {
        if currentTrack != nil { host?.systemMusicPrefetchNext() }
    }

    private func startIfNeeded() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.handleInterruption(note) }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.handleRouteChange(note) }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recoverAfterMediaReset() }
        })
        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.resumeAfterInterruption,
                      !self.userPaused else { return }
                self.resumeAfterInterruption = false
                self.host?.systemMusicResume()
            }
        })
        callCancellable = CallCenter.shared.$phase.sink { [weak self] phase in
            Task { @MainActor in
                self?.host?.systemMusicDucking(phase == .active)
            }
        }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.networkConstrained = path.isConstrained
                self?.networkExpensive = path.isExpensive
            }
        }
        pathMonitor.start(queue: pathQueue)
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            guard host?.systemMusicIsPlaying == true else { return }
            resumeAfterInterruption = true
            state = .interrupted
            host?.systemMusicPauseForInterruption()
        case .ended:
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            let shouldResume = options.contains(.shouldResume)
            if shouldResume, resumeAfterInterruption, !userPaused {
                resumeAfterInterruption = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    guard let self, !self.userPaused else { return }
                    self.host?.systemMusicResume()
                }
            } else {
                resumeAfterInterruption = false
                state = userPaused ? .paused : .interrupted
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        switch reason {
        case .oldDeviceUnavailable:
            routePaused = true
            resumeAfterInterruption = false
            if host?.systemMusicIsPlaying == true {
                host?.systemMusicPauseForInterruption()
            }
            state = .paused
        case .newDeviceAvailable:
            if routePaused, !userPaused, currentTrack != nil {
                routePaused = false
                _ = activateSession()
                host?.systemMusicResume()
            }
        case .routeConfigurationChange:
            if host?.systemMusicIsPlaying == true {
                host?.systemMusicResume()
            }
        case .override:
            _ = activateSession()
        default:
            break
        }
    }

    private func recoverAfterMediaReset() {
        let saved = host?.systemMusicPosition ?? position
        state = .recovering
        host?.systemMusicPauseForInterruption()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self else { return }
            _ = self.activateSession()
            self.host?.systemMusicRecover(at: saved)
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled, let self, self.playing else { return }
                self.report(force: true)
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    private func report(force: Bool) {
        guard let track = currentTrack else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastReportAt) < 15 { return }
        lastReportAt = now
        let p = position
        let d = duration
        let active = playing
        Task {
            await API.shared.musicNow(
                track,
                playing: active,
                seconds: p,
                duration: d
            )
        }
    }
}
