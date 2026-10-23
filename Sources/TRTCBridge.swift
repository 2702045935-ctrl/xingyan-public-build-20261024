import Foundation
import UIKit
import SwiftUI
import TXLiteAVSDK_TRTC

@MainActor
final class TRTCBridge: NSObject, ObservableObject {
    static let shared = TRTCBridge()

    @Published private(set) var joined = false

    @Published private(set) var remoteView: UIView? = nil

    private var meetingViews: [String: UIView] = [:]

    @Published private(set) var meetingUsers: [String] = []

    func meetingView(for userId: String) -> UIView {
        if let v = meetingViews[userId] { return v }
        let v = UIView()
        v.backgroundColor = .black
        meetingViews[userId] = v
        if !meetingUsers.contains(userId) { meetingUsers.append(userId) }
        cloud?.startRemoteView(userId, view: v)
        return v
    }

    func stopMeetingViews() {
        for (id, _) in meetingViews { cloud?.stopRemoteView(id) }
        meetingViews.removeAll()
        meetingUsers.removeAll()
    }

    @Published private(set) var localView: UIView? = nil

    @Published private(set) var peerInRoom = false

    @Published private(set) var lastError = ""

    @Published private(set) var userId = ""

    @Published private(set) var audioQualityLabel = "50kbps"

    @Published private(set) var networkQuality = 0

    var onJoined: ((Bool) -> Void)?
    var onPeerChanged: ((Bool) -> Void)?

    private var cloud: TRTCCloud?
    private var roomSeed = ""
    private var isVideo = false
    private var busy = false

    private var peerUserId = ""

    private var active = false
    private var muted = false

    private var micReady = false

    private var lastLocalAudioBitrate: UInt32 = 0
    private var lastRemoteAudioBitrate: UInt32 = 0
    private var lastAudioPacketLoss: UInt32 = 0
    private var lastJitterBuffer: UInt32 = 0
    private var lastPointToPointDelay: UInt32 = 0
    private var lastAudioBlockRate: UInt32 = 0
    private var lastRTT: UInt32 = 0
    private var lastUpLoss: UInt32 = 0
    private var lastDownLoss: UInt32 = 0
    private var micRecoveryCount = 0
    private var audioQuality: TRTCAudioQuality = .default
    private var pendingQuality: TRTCAudioQuality?
    private var qualityTask: Task<Void, Never>?
    private var micWatchTask: Task<Void, Never>?

    private var prefsObserver: NSObjectProtocol? = nil

    private override init() { super.init() }

    var diagSummary: String {
        "TRTC 档位=\(audioQualityLabel) 网络=\(networkQuality) "
            + "RTT=\(lastRTT)ms 上行丢包=\(lastUpLoss)% 下行丢包=\(lastDownLoss)% "
            + "本地音频=\(lastLocalAudioBitrate)kbps 远端音频=\(lastRemoteAudioBitrate)kbps "
            + "音频丢包=\(lastAudioPacketLoss)% 抖动缓存=\(lastJitterBuffer)ms "
            + "路径延迟=\(lastPointToPointDelay)ms 卡顿率=\(lastAudioBlockRate)% "
            + "麦克风就绪=\(micReady ? "是" : "否") 重试=\(micRecoveryCount)次"
    }

    @discardableResult
    func start(roomSeed: String, video: Bool) async -> Bool {
        guard !joined, !busy else { return joined }
        busy = true
        defer { busy = false }
        self.roomSeed = roomSeed
        isVideo = video
        lastError = ""
        resetWeakNetworkState()

        let cfg: API.TRTCSig
        do {
            cfg = try await API.shared.trtcSig(room: roomSeed, media: video ? "video" : "audio")
        } catch {
            lastError = (error as? APIError)?.errorDescription ?? "TRTC 取不到签名"
            return false
        }
        guard cfg.sdkAppId > 0, !cfg.userSig.isEmpty, cfg.roomId > 0 else {
            lastError = "TRTC 参数不完整"
            return false
        }

        let params = TRTCParams()
        params.sdkAppId = UInt32(cfg.sdkAppId)
        params.userId = cfg.userId
        userId = cfg.userId
        params.userSig = cfg.userSig
        params.roomId = UInt32(cfg.roomId)
        params.role = .anchor

        let c = TRTCCloud.sharedInstance()
        c.delegate = self
        cloud = c
        // 弱网优先保流畅：云端自动控速，视频编码允许自动降分辨率。
        let qos = TRTCNetworkQosParam()
        if let pref = TRTCVideoQosPreference(rawValue: 1) { qos.preference = pref }
        if let mode = TRTCQosControlMode(rawValue: 1) { qos.controlMode = mode }
        c.setNetworkQosParam(qos)
        if prefsObserver == nil {
            prefsObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name("chrisCallPrefsChanged"), object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.applyVideoPrefs()
                    self?.applyBeauty()
                }
            }
        }
        remoteView = UIView()
        localView = UIView()

        applyVoiceEffect()

        c.enterRoom(params, appScene: video ? .videoCall : .audioCall)
        return true
    }

    func activate() {
        guard let c = cloud, joined, !active else { return }
        active = true
        micReady = false
        c.startLocalAudio(audioQuality)
        c.muteLocalAudio(false)
        scheduleMicRecoveryWatch()
        if isVideo {

            applyVideoPrefs()
            c.startLocalPreview(true, view: localView)

            if VideoBlur.shared.enabled { setBackgroundBlur(true) }
        }
    }

    func applyVideoPrefs() {
        guard let c = cloud, isVideo else { return }
        let p = CallPrefs.encoderParams()
        let enc = TRTCVideoEncParam()
        if let res = TRTCVideoResolution(rawValue: p.resolution) { enc.videoResolution = res }
        if let mode = TRTCVideoResolutionMode(rawValue: 1) { enc.resMode = mode }
        enc.videoFps = p.fps
        enc.videoBitrate = p.bitrate
        enc.enableAdjustRes = true
        c.setVideoEncoderParam(enc)

        let r = TRTCRenderParams()
        if let fill = TRTCVideoFillMode(rawValue: 0) { r.fillMode = fill }
        if let mir = TRTCVideoMirrorType(rawValue: CallPrefs.mirror ? 1 : 2) { r.mirrorType = mir }
        c.setLocalRenderParams(r)

        applyBeauty()
    }

    func applyBeauty() {
        guard let mgr = cloud?.getBeautyManager() else { return }
        if let style = TXBeautyStyle(rawValue: 1) { mgr.setBeautyStyle(style) }
        let lv = Float(CallPrefs.beauty)
        mgr.setBeautyLevel(lv * 3)
        mgr.setWhitenessLevel(lv * 1.5)
    }

    func setBackgroundBlur(_ on: Bool) {
        guard let c = cloud, let fmt = TRTCVideoPixelFormat(rawValue: 6),
              let buf = TRTCVideoBufferType(rawValue: 1) else { return }
        if on, isVideo {
            c.setLocalVideoProcessDelegete(VideoBlur.shared, pixelFormat: fmt, bufferType: buf)
        } else {
            c.setLocalVideoProcessDelegete(nil, pixelFormat: fmt, bufferType: buf)
            VideoBlur.shared.reset()
        }
    }

    func applyVoiceEffect() {
        guard let mgr = cloud?.getAudioEffectManager() else { return }
        let e = VoiceChangerStore.shared.current
        if let t = TXVoiceChangeType(rawValue: e.trtcChange) {
            mgr.setVoiceChangerType(t)
        }
        if let r = TXVoiceReverbType(rawValue: e.trtcReverb) {
            mgr.setVoiceReverbType(r)
        }
    }

    func standByForLocalMedia() {
        guard let c = cloud, joined else { return }

        guard active else { return }
        micWatchTask?.cancel()
        micWatchTask = nil
        c.stopLocalAudio()
        if isVideo { c.stopLocalPreview() }
        active = false
    }

    func stop() {
        qualityTask?.cancel()
        qualityTask = nil
        micWatchTask?.cancel()
        micWatchTask = nil
        if let ob = prefsObserver {
            NotificationCenter.default.removeObserver(ob)
            prefsObserver = nil
        }
        cloud?.stopLocalPreview()
        cloud?.stopLocalAudio()
        if !peerUserId.isEmpty { cloud?.stopRemoteView(peerUserId) }
        cloud?.exitRoom()
        cloud?.delegate = nil
        cloud = nil
        TRTCCloud.destroySharedInstance()
        joined = false
        peerInRoom = false
        peerUserId = ""
        active = false
        resetWeakNetworkState()
        remoteView = nil
        localView = nil
    }

    func setMuted(_ mute: Bool) {
        muted = mute
        cloud?.muteLocalAudio(mute)
    }

    func setCameraOff(_ off: Bool) {
        guard isVideo else { return }
        if off { cloud?.stopLocalPreview() } else { cloud?.startLocalPreview(true, view: localView) }
    }

    func flipCamera() {
        cloud?.switchCamera()
    }

    func setSpeaker(_ on: Bool) {

        if let route = TRTCAudioRoute(rawValue: on ? 0 : 1) {
            cloud?.setAudioRoute(route)
        }
    }

    private func resetWeakNetworkState() {
        qualityTask?.cancel()
        qualityTask = nil
        micWatchTask?.cancel()
        micWatchTask = nil
        pendingQuality = nil
        audioQuality = .default
        audioQualityLabel = "50kbps"
        networkQuality = 0
        muted = false
        micReady = false
        micRecoveryCount = 0
        lastLocalAudioBitrate = 0
        lastRemoteAudioBitrate = 0
        lastAudioPacketLoss = 0
        lastJitterBuffer = 0
        lastPointToPointDelay = 0
        lastAudioBlockRate = 0
        lastRTT = 0
        lastUpLoss = 0
        lastDownLoss = 0
    }

    private func scheduleAudioQuality(_ target: TRTCAudioQuality) {
        guard active else { return }
        if pendingQuality == target { return }

        if target == .default,
           audioQuality == .speech,
           pendingQuality == .speech {
            return
        }
        if target == .speech,
           audioQuality == .speech,
           pendingQuality == nil {
            return
        }
        if target == .default,
           audioQuality == .default,
           pendingQuality == nil {
            return
        }
        qualityTask?.cancel()
        pendingQuality = target
        let delay: UInt64 = target == .speech ? 1_200_000_000 : 8_000_000_000
        qualityTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self = self, !Task.isCancelled, self.active else { return }
            self.pendingQuality = nil
            guard self.audioQuality != target else { return }
            self.audioQuality = target
            self.audioQualityLabel = target == .speech ? "18kbps" : "50kbps"
            self.cloud?.startLocalAudio(target)
            self.cloud?.muteLocalAudio(self.muted)
        }
    }

    private func scheduleMicRecoveryWatch() {
        micWatchTask?.cancel()
        micWatchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard let self = self, !Task.isCancelled, self.active,
                  !self.micReady, self.lastLocalAudioBitrate == 0 else { return }
            guard self.micRecoveryCount < 1 else { return }
            self.micRecoveryCount += 1
            self.lastError = "TRTC 麦克风未确认，已自动重试"
            self.cloud?.stopLocalAudio()
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let c = self.cloud, self.active, !Task.isCancelled else { return }
            c.startLocalAudio(self.audioQuality)
            c.muteLocalAudio(self.muted)
        }
    }
}

extension TRTCBridge: TRTCCloudDelegate {
    nonisolated func onEnterRoom(_ result: Int) {
        Task { @MainActor in
            if result > 0 {
                self.joined = true
                self.lastError = ""
                self.onJoined?(true)
            } else {
                self.joined = false
                self.lastError = "TRTC 进房失败（错误码 \(result)）"
                self.onJoined?(false)
            }
        }
    }

    nonisolated func onExitRoom(_ reason: Int) {
        Task { @MainActor in
            self.joined = false
            self.peerInRoom = false
            self.onJoined?(false)
        }
    }

    nonisolated func onRemoteUserEnterRoom(_ userId: String) {
        Task { @MainActor in
            self.peerUserId = userId
            self.peerInRoom = true
            self.onPeerChanged?(true)
        }
    }

    nonisolated func onRemoteUserLeaveRoom(_ userId: String, reason: Int) {
        Task { @MainActor in
            self.peerInRoom = false
            self.onPeerChanged?(false)
        }
    }

    nonisolated func onUserVideoAvailable(_ userId: String, available: Bool) {
        Task { @MainActor in

            if let v = self.meetingViews[userId] {
                if available { self.cloud?.startRemoteView(userId, view: v) }
                else { self.cloud?.stopRemoteView(userId) }
                return
            }
            if available, let v = self.remoteView {
                self.peerUserId = userId
                self.cloud?.startRemoteView(userId, view: v)
                self.peerInRoom = true
                self.onPeerChanged?(true)
            } else {
                self.cloud?.stopRemoteView(userId)
            }
        }
    }

    nonisolated func onUserAudioAvailable(_ userId: String, available: Bool) {
        Task { @MainActor in
            guard available else { return }
            self.peerUserId = userId
            self.peerInRoom = true
            self.onPeerChanged?(true)
        }
    }

    nonisolated func onNetworkQuality(_ localQuality: TRTCQualityInfo,
                                      remoteQuality: [TRTCQualityInfo]) {
        Task { @MainActor in
            guard self.active else { return }
            let worst = max(localQuality.quality.rawValue,
                            remoteQuality.map { $0.quality.rawValue }.max() ?? 0)
            self.networkQuality = worst
            if worst >= 4 {
                self.scheduleAudioQuality(.speech)
            } else if worst > 0 && worst <= 2 {
                self.scheduleAudioQuality(.default)
            }
        }
    }

    nonisolated func onStatistics(_ statistics: TRTCStatistics) {
        Task { @MainActor in
            guard self.active else { return }
            self.lastRTT = statistics.rtt
            self.lastUpLoss = statistics.upLoss
            self.lastDownLoss = statistics.downLoss
            self.lastLocalAudioBitrate = statistics.localStatistics
                .map { $0.audioBitrate }.max() ?? 0
            if self.lastLocalAudioBitrate > 0 {
                self.micReady = true
                self.micWatchTask?.cancel()
                self.micWatchTask = nil
            }
            guard let remote = statistics.remoteStatistics.first else { return }
            self.lastRemoteAudioBitrate = remote.audioBitrate
            self.lastAudioPacketLoss = remote.audioPacketLoss
            self.lastJitterBuffer = remote.jitterBufferDelay
            self.lastPointToPointDelay = remote.point2PointDelay
            self.lastAudioBlockRate = remote.audioBlockRate
            let weakAudio = remote.audioPacketLoss >= 4
                || remote.jitterBufferDelay >= 500
                || remote.point2PointDelay >= 700
                || remote.audioBlockRate >= 1
                || statistics.upLoss >= 8
                || statistics.downLoss >= 8
                || statistics.rtt >= 300
            let stableAudio = remote.audioPacketLoss < 1
                && remote.jitterBufferDelay < 120
                && remote.point2PointDelay < 250
                && remote.audioBlockRate == 0
                && statistics.upLoss < 2
                && statistics.downLoss < 2
                && statistics.rtt < 150
            if weakAudio {
                self.scheduleAudioQuality(.speech)
            } else if stableAudio {
                self.scheduleAudioQuality(.default)
            }
        }
    }

    nonisolated func onMicDidReady() {
        Task { @MainActor in
            self.micReady = true
            self.micWatchTask?.cancel()
            self.micWatchTask = nil
            if self.lastError.contains("麦克风未确认") {
                self.lastError = ""
            }
        }
    }

    nonisolated func onConnectionLost() {
        Task { @MainActor in
            self.networkQuality = 6
            self.scheduleAudioQuality(.speech)
        }
    }

    nonisolated func onConnectionRecovery() {
        Task { @MainActor in
            self.networkQuality = 2
            self.scheduleAudioQuality(.default)
        }
    }

    nonisolated func onError(_ errCode: Int, errMsg: String?, extInfo: [String: Any]?) {
        Task { @MainActor in
            self.lastError = "TRTC 错误 \(errCode)：" + (errMsg ?? "")
        }
    }
}

struct TRTCVideoView: UIViewRepresentable {
    let view: UIView?

    func makeUIView(context: Context) -> UIView {
        let holder = UIView()
        holder.backgroundColor = .clear
        if let v = view {
            v.frame = holder.bounds
            v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            holder.addSubview(v)
        }
        return holder
    }

    func updateUIView(_ holder: UIView, context: Context) {
        guard let v = view else { return }
        if v.superview !== holder {
            v.frame = holder.bounds
            v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            holder.addSubview(v)
        }
    }
}
