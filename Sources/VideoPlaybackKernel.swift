import AVFoundation
import Foundation
import Network
import UIKit

struct VideoPlaybackProfile {
    var expensiveNetwork = false
    var constrainedNetwork = false
    var lowPowerMode = false
    var thermalLevel = 0
    var memoryPressure = false
    var hardwarePlayerLimit = 4
    var hardwareLookAhead = 2

    var reducesWork: Bool {
        lowPowerMode || memoryPressure || thermalLevel >= 2
    }

    var playerLimit: Int {
        min(reducesWork ? 2 : 4, hardwarePlayerLimit)
    }
    var lookAhead: Int {
        min(reducesWork ? 1 : 2, hardwareLookAhead)
    }
    var activeBufferSeconds: Double {
        if constrainedNetwork { return 3.0 }
        if expensiveNetwork { return 2.2 }
        return 1.4
    }
    var preloadBufferSeconds: Double {
        if constrainedNetwork { return 1.4 }
        if expensiveNetwork { return 0.9 }
        return 0.55
    }
    var peakBitRate: Double {
        if constrainedNetwork { return 900_000 }
        if expensiveNetwork { return 1_800_000 }
        return 4_000_000
    }
    var waitsToMinimizeStalling: Bool {
        constrainedNetwork || expensiveNetwork
    }
    var firstFrameTimeout: TimeInterval {
        constrainedNetwork ? 4.5 : 2.8
    }
}

final class VideoPlaybackPolicy {
    static let shared = VideoPlaybackPolicy()

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "chris.video.network")
    private let lock = NSLock()
    private var expensive = false
    private var constrained = false
    private var started = false
    private var observers: [NSObjectProtocol] = []

    private init() {}

    func start() {
        lock.lock()
        guard !started else {
            lock.unlock()
            return
        }
        started = true
        lock.unlock()

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.expensive = path.isExpensive
            self.constrained = path.isConstrained
            self.lock.unlock()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .chrisVideoProfileChanged, object: nil)
            }
        }
        monitor.start(queue: monitorQueue)

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            NotificationCenter.default.post(name: .chrisVideoProfileChanged, object: nil)
        })
        observers.append(center.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { _ in
            NotificationCenter.default.post(name: .chrisVideoProfileChanged, object: nil)
        })
        observers.append(center.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            NotificationCenter.default.post(name: .chrisVideoMemoryWarning, object: nil)
        })
    }

    var profile: VideoPlaybackProfile {
        lock.lock()
        let expensive = self.expensive
        let constrained = self.constrained
        lock.unlock()
        let thermal: Int
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = 0
        case .fair: thermal = 1
        case .serious: thermal = 2
        case .critical: thermal = 3
        @unknown default: thermal = 1
        }
        let hardware = DevicePerformanceProfile.shared
        return VideoPlaybackProfile(
            expensiveNetwork: expensive,
            constrainedNetwork: constrained,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalLevel: thermal,
            memoryPressure: false,
            hardwarePlayerLimit: hardware.videoPlayerLimit,
            hardwareLookAhead: hardware.videoLookAhead
        )
    }
}

extension Notification.Name {
    static let chrisVideoMemoryWarning = Notification.Name("chris.video.memory-warning")
    static let chrisVideoProfileChanged = Notification.Name("chris.video.profile-changed")
}

final class PlayerPool: ObservableObject {
    static let shared = PlayerPool()

    enum SourceKind {
        case local
        case hls
        case mp4
    }

    struct Source {
        let url: URL
        let kind: SourceKind
    }

    private final class Entry {
        let item: FeedItem
        let player = AVPlayer()
        var sources: [Source] = []
        var sourceIndex = 0
        var observations: [NSKeyValueObservation] = []
        var notifications: [NSObjectProtocol] = []
        var firstFrameTask: Task<Void, Never>?
        var recoveryTask: Task<Void, Never>?
        var pendingSeek: TimeInterval = 0
        var reloadCount = 0
        var switching = false
        var lastAccess = Date()

        init(item: FeedItem) {
            self.item = item
        }
    }

    @Published var currentId: String = ""
    @Published private(set) var loading: Set<String> = []
    @Published private(set) var ready: Set<String> = []
    @Published private(set) var failed: Set<String> = []

    private let policy = VideoPlaybackPolicy.shared
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var played: Set<String> = []
    private var wantsPlayback = false
    private var memoryPressure = false
    private var systemObservers: [NSObjectProtocol] = []

    private init() {
        policy.start()
        let center = NotificationCenter.default
        systemObservers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.pauseAll()
        })
        systemObservers.append(center.addObserver(
            forName: .chrisVideoMemoryWarning,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.memoryPressure = true
            self?.trimInactiveEntries(force: true)
        })
        systemObservers.append(center.addObserver(
            forName: .chrisVideoProfileChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.trimInactiveEntries()
        })
    }

    deinit {
        systemObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func player(for item: FeedItem) -> AVPlayer? {
        touch(item.id)
        if let existing = entries[item.id] { return existing.player }
        let sources = sourcePlan(item)
        guard !sources.isEmpty else {
            failed.insert(item.id)
            return nil
        }

        let entry = Entry(item: item)
        entry.sources = sources
        entry.player.actionAtItemEnd = .none
        entry.player.isMuted = currentId != item.id
        entries[item.id] = entry
        loading.insert(item.id)
        installSource(entry, index: 0, seekTo: 0)
        return entry.player
    }

    func focus(items: [FeedItem], index: Int) {
        guard !items.isEmpty else {
            currentId = ""
            releaseAll()
            return
        }
        let safeIndex = max(0, min(index, items.count - 1))
        let item = items[safeIndex]
        currentId = item.id
        touch(item.id)

        let profile = currentProfile
        let lower = profile.reducesWork ? safeIndex : max(0, safeIndex - 1)
        let upper = min(items.count - 1, safeIndex + profile.lookAhead)
        var keep = Set<String>()
        for i in lower...upper {
            keep.insert(items[i].id)
            _ = player(for: items[i])
        }

        for (id, entry) in entries {
            entry.player.isMuted = id != currentId
            if id != currentId { entry.player.pause() }
        }
        trimInactiveEntries(keeping: keep)
    }

    func play(_ item: FeedItem) {
        guard currentId == item.id else { return }
        guard let entry = player(for: item).flatMap({ _ in entries[item.id] }) else { return }
        wantsPlayback = true
        activateAudioSession()
        entry.player.isMuted = false
        entry.player.playImmediately(atRate: 1)
        startFirstFrameMonitor(entry)
    }

    func pause(_ item: FeedItem) {
        guard let entry = entries[item.id] else { return }
        entry.player.pause()
        entry.player.isMuted = true
        if currentId == item.id {
            wantsPlayback = false
        }
    }

    func retry(_ item: FeedItem) {
        releaseEntry(item.id)
        failed.remove(item.id)
        loading.remove(item.id)
        ready.remove(item.id)
        played.remove(item.id)
        _ = player(for: item)
        if currentId == item.id {
            play(item)
        }
    }

    func progress(of id: String) -> Double {
        guard let p = entries[id]?.player, let item = p.currentItem else { return 0 }
        let total = CMTimeGetSeconds(item.duration)
        let current = CMTimeGetSeconds(p.currentTime())
        guard total.isFinite, total > 0, current.isFinite else { return 0 }
        return max(0, min(1, current / total))
    }

    func hasPlayed(_ id: String) -> Bool {
        played.contains(id)
    }

    func isReady(_ id: String) -> Bool {
        ready.contains(id)
    }

    func keepOnly(_ ids: [String]) {
        trimInactiveEntries(keeping: Set(ids))
    }

    func suspend() {
        wantsPlayback = false
        pauseAll()
    }

    func releaseAll() {
        let keys = entries.keys
        for key in keys {
            releaseEntry(key)
        }
        ready.removeAll()
        loading.removeAll()
        failed.removeAll()
        played.removeAll()
    }

    private var currentProfile: VideoPlaybackProfile {
        var profile = policy.profile
        profile.memoryPressure = memoryPressure
        return profile
    }

    private func sourcePlan(_ item: FeedItem) -> [Source] {
        var out: [Source] = []
        let videoURL = item.video.flatMap {
            $0.isEmpty ? nil : API.shared.assetURL($0)
        }
        if let video = item.video, !video.isEmpty,
           let remote = API.shared.assetURL(video) {
            if let local = LocalStore.localURL(remote.path),
               FileManager.default.fileExists(atPath: local.path) {
                out.append(Source(url: local, kind: .local))
            }
        }
        let hlsURL = item.hls.flatMap {
            $0.isEmpty ? nil : API.shared.assetURL($0)
        }
        /* 刚发布的作品优先原片。HLS 是后台异步生成的，立刻先挂 HLS
           会有一小段目录/分片还没齐的空白窗口；原片反而能立即出首帧。 */
        let preferOriginal = item.mine == true && isRecentUpload(item.createdAt)
        if preferOriginal, let videoURL {
            out.append(Source(url: videoURL, kind: .mp4))
        }
        if let hlsURL {
            out.append(Source(url: hlsURL, kind: .hls))
        }
        if !preferOriginal, let videoURL,
           !out.contains(where: { $0.url == videoURL }) {
            out.append(Source(url: videoURL, kind: .mp4))
        }
        if out.isEmpty, let url = API.shared.assetURL(item.playPath) {
            out.append(Source(url: url, kind: url.pathExtension == "m3u8" ? .hls : .mp4))
        }
        return out
    }

    private func isRecentUpload(_ value: String?) -> Bool {
        guard let date = TimeFmt.date(value) else { return false }
        return Date().timeIntervalSince(date) < 30 * 60
    }

    private func installSource(_ entry: Entry, index: Int, seekTo: TimeInterval) {
        guard index >= 0, index < entry.sources.count else {
            markFailed(entry)
            return
        }
        let profile = currentProfile
        let source = entry.sources[index]
        let item: AVPlayerItem
        switch source.kind {
        case .hls, .mp4:
            item = StreamPlay.item(source.url) ?? AVPlayerItem(url: source.url)
        case .local:
            item = AVPlayerItem(url: source.url)
        }
        item.preferredForwardBufferDuration = currentId == entry.item.id
            ? profile.activeBufferSeconds
            : profile.preloadBufferSeconds
        item.preferredPeakBitRate = profile.peakBitRate
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        item.startsOnFirstEligibleVariant = true

        clearObservers(entry)
        entry.sourceIndex = index
        entry.pendingSeek = max(0, seekTo)
        entry.player.automaticallyWaitsToMinimizeStalling = profile.waitsToMinimizeStalling
        let old = entry.player.currentItem
        entry.player.replaceCurrentItem(with: item)
        if old !== item {
            StreamPlay.cancel(old)
        }
        observe(entry, item: item)
        CrashCatcher.note(
            "视频号",
            "播放源 id=\(entry.item.id) #\(index) \(source.kind == .hls ? "HLS" : source.kind == .local ? "本地" : "MP4") \(source.url.absoluteString)"
        )
        if currentId == entry.item.id {
            entry.player.isMuted = false
            entry.player.playImmediately(atRate: 1)
            startFirstFrameMonitor(entry)
        }
    }

    private func observe(_ entry: Entry, item: AVPlayerItem) {
        entry.observations.append(item.observe(\.status, options: [.initial, .new]) {
            [weak self, weak entry, weak item] _, _ in
            DispatchQueue.main.async {
                guard let self, let entry, let item,
                      entry.player.currentItem === item else { return }
                if item.status == .failed {
                    self.recover(entry, reason: item.error?.localizedDescription ?? "媒体加载失败")
                } else if item.status == .readyToPlay {
                    if entry.pendingSeek > 0 {
                        let target = CMTime(seconds: entry.pendingSeek, preferredTimescale: 600)
                        entry.pendingSeek = 0
                        entry.player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
                    }
                    self.ready.insert(entry.item.id)
                    self.loading.remove(entry.item.id)
                    if self.currentId != entry.item.id {
                        entry.player.preroll(atRate: 1.0) { _ in }
                    } else if self.wantsPlayback {
                        entry.player.playImmediately(atRate: 1)
                    }
                }
            }
        })
        entry.observations.append(item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) {
            [weak self, weak entry, weak item] _, _ in
            DispatchQueue.main.async {
                guard let self, let entry, let item,
                      entry.player.currentItem === item else { return }
                if item.isPlaybackLikelyToKeepUp {
                    self.ready.insert(entry.item.id)
                    self.loading.remove(entry.item.id)
                }
            }
        })

        let center = NotificationCenter.default
        entry.notifications.append(center.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak entry, weak item] _ in
            guard let self, let entry, let item,
                  entry.player.currentItem === item else { return }
            Task { @MainActor in
                VideoKernelTelemetry.shared.complete(entry.item.id)
            }
            entry.player.seek(to: .zero)
            if self.currentId == entry.item.id, self.wantsPlayback {
                entry.player.playImmediately(atRate: 1)
            }
        })
        entry.notifications.append(center.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak entry, weak item] note in
            guard let self, let entry, let item,
                  entry.player.currentItem === item else { return }
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            self.recover(entry, reason: error?.localizedDescription ?? "播放中断")
        })
        entry.notifications.append(center.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self, weak entry, weak item] _ in
            guard let self, let entry, let item,
                  entry.player.currentItem === item else { return }
            self.scheduleStallRecovery(entry)
        })
    }

    private func startFirstFrameMonitor(_ entry: Entry) {
        entry.firstFrameTask?.cancel()
        entry.firstFrameTask = Task { @MainActor [weak self, weak entry] in
            guard let self, let entry else { return }
            let started = Date()
            var lastTime = -1.0
            var lastProgressAt = started
            var gotFrame = self.played.contains(entry.item.id)

            while !Task.isCancelled {
                guard self.entries[entry.item.id] === entry,
                      self.currentId == entry.item.id,
                      self.wantsPlayback else { return }
                let player = entry.player
                let currentItem = player.currentItem
                if currentItem?.status == .failed {
                    self.recover(entry, reason: currentItem?.error?.localizedDescription ?? "加载失败")
                    return
                }

                let seconds = CMTimeGetSeconds(player.currentTime())
                if seconds.isFinite, seconds > lastTime + 0.015 {
                    lastTime = seconds
                    lastProgressAt = Date()
                    if !gotFrame {
                        gotFrame = true
                        self.played.insert(entry.item.id)
                        self.ready.insert(entry.item.id)
                        self.loading.remove(entry.item.id)
                        VideoKernelTelemetry.shared.event("first_frame", itemId: entry.item.id)
                        let ms = Int(Date().timeIntervalSince(started) * 1000)
                        CrashCatcher.note("视频号", "首帧 id=\(entry.item.id) \(ms)ms")
                    }
                } else {
                    let elapsed = Date().timeIntervalSince(started)
                    if !gotFrame, elapsed >= self.currentProfile.firstFrameTimeout {
                        self.recover(entry, reason: "首帧超时 \(Int(elapsed * 1000))ms")
                        return
                    }
                    if gotFrame,
                       Date().timeIntervalSince(lastProgressAt) >= 1.45,
                       player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                        self.recover(entry, reason: "播放停滞")
                        return
                    }
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func scheduleStallRecovery(_ entry: Entry) {
        guard currentId == entry.item.id, wantsPlayback, !entry.switching else { return }
        entry.recoveryTask?.cancel()
        entry.recoveryTask = Task { @MainActor [weak self, weak entry] in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled, let self, let entry,
                  self.currentId == entry.item.id,
                  self.wantsPlayback else { return }
            self.recover(entry, reason: "系统报告播放停滞")
        }
    }

    private func recover(_ entry: Entry, reason: String) {
        guard !entry.switching else { return }
        if currentId != entry.item.id {
            releaseEntry(entry.item.id)
            return
        }
        entry.switching = true
        let seconds = CMTimeGetSeconds(entry.player.currentTime())
        let keepPosition = seconds.isFinite ? max(0, seconds) : 0
        Task { @MainActor in
            VideoKernelTelemetry.shared.event("playback_error", itemId: entry.item.id)
        }
        CrashCatcher.note(
            "视频号",
            "播放自愈 id=\(entry.item.id) 原因=\(reason) 当前源=\(entry.sourceIndex) 进度=\(String(format: "%.2f", keepPosition))"
        )

        if entry.sourceIndex + 1 < entry.sources.count {
            let next = entry.sourceIndex + 1
            entry.switching = false
            installSource(entry, index: next, seekTo: keepPosition)
            return
        }
        if entry.reloadCount < 1 {
            entry.reloadCount += 1
            entry.recoveryTask?.cancel()
            entry.recoveryTask = Task { @MainActor [weak self, weak entry] in
                try? await Task.sleep(nanoseconds: 850_000_000)
                guard !Task.isCancelled, let self, let entry else { return }
                entry.switching = false
                self.installSource(entry, index: 0, seekTo: keepPosition)
            }
            return
        }
        entry.switching = false
        markFailed(entry)
    }

    private func markFailed(_ entry: Entry) {
        failed.insert(entry.item.id)
        loading.remove(entry.item.id)
        entry.player.pause()
        CrashCatcher.note("视频号", "播放失败 id=\(entry.item.id)")
    }

    private func trimInactiveEntries(keeping: Set<String> = [], force: Bool = false) {
        let limit = currentProfile.playerLimit
        var removable = entries.values
            .filter { $0.item.id != currentId && !keeping.contains($0.item.id) }
            .sorted { $0.lastAccess < $1.lastAccess }
        if force {
            removable = entries.values
                .filter { $0.item.id != currentId }
                .sorted { $0.lastAccess < $1.lastAccess }
        }
        while entries.count > limit, let victim = removable.first {
            removable.removeFirst()
            releaseEntry(victim.item.id)
        }
    }

    private func releaseEntry(_ id: String) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        entry.firstFrameTask?.cancel()
        entry.recoveryTask?.cancel()
        clearObservers(entry)
        entry.player.pause()
        StreamPlay.cancel(entry.player.currentItem)
        entry.player.replaceCurrentItem(with: nil)
        loading.remove(id)
        ready.remove(id)
    }

    private func clearObservers(_ entry: Entry) {
        entry.observations.forEach { $0.invalidate() }
        entry.observations.removeAll()
        entry.notifications.forEach(NotificationCenter.default.removeObserver)
        entry.notifications.removeAll()
    }

    private func touch(_ id: String) {
        entries[id]?.lastAccess = Date()
    }

    private func pauseAll() {
        for entry in entries.values {
            entry.player.pause()
            entry.player.isMuted = true
            entry.firstFrameTask?.cancel()
            entry.recoveryTask?.cancel()
        }
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? session.setActive(true)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element {
        self[Swift.max(0, Swift.min(index, count - 1))]
    }
}
