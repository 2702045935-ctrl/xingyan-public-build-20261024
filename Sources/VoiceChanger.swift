import Foundation
import AVFoundation
import SwiftUI
import TXLiteAVSDK_TRTC

struct VoiceEffect: Identifiable, Equatable {
    let id: String
    let name: String
    let hint: String

    let trtcChange: Int
    let trtcReverb: Int

    let speed: Float
    let pitch: Float
    let lowGain: Float
    let highGain: Float
    let wet: Float
}

@MainActor
final class VoiceChangerStore: ObservableObject {
    static let shared = VoiceChangerStore()

    static let all: [VoiceEffect] = [
        VoiceEffect(id: "origin", name: "原声", hint: "不做任何处理",
                    trtcChange: 0, trtcReverb: 0,
                    speed: 1.0, pitch: 0, lowGain: 0, highGain: 0, wet: 0),

        VoiceEffect(id: "girl", name: "温柔女声", hint: "真女声的嗓子（不是小孩音那种假声）",
                    trtcChange: 2, trtcReverb: 0,
                    speed: 1.19, pitch: 0, lowGain: -3, highGain: 2.5, wet: 0),

        VoiceEffect(id: "uncle", name: "磁性男声", hint: "低沉、有厚度，成熟男人的嗓子",
                    trtcChange: 3, trtcReverb: 7,
                    speed: 0.88, pitch: 0, lowGain: 3.5, highGain: -2.5, wet: 0),

        VoiceEffect(id: "boy", name: "清亮少年", hint: "年轻、干净，像二十来岁的小伙子",
                    trtcChange: 0, trtcReverb: 9,
                    speed: 1.10, pitch: 0, lowGain: -1.5, highGain: 1.6, wet: 0),

        VoiceEffect(id: "kidboy", name: "小男孩", hint: "童声，像七八岁的小男孩",
                    trtcChange: 1, trtcReverb: 0,
                    speed: 1.30, pitch: 0, lowGain: -2, highGain: 1.2, wet: 0),

        VoiceEffect(id: "kidgirl", name: "小女孩", hint: "童声，像七八岁的小女孩",
                    trtcChange: 2, trtcReverb: 0,
                    speed: 1.40, pitch: 0, lowGain: -3, highGain: 2.0, wet: 0),

        VoiceEffect(id: "radio", name: "电台主播", hint: "贴耳的低沉嗓 + 录音棚质感",
                    trtcChange: 0, trtcReverb: 9,
                    speed: 0.94, pitch: 0, lowGain: 2.5, highGain: 1.5, wet: 8),

        VoiceEffect(id: "ethereal", name: "空灵嗓", hint: "轻、软、带一点空间感（还是真人嗓）",
                    trtcChange: 11, trtcReverb: 8,
                    speed: 1.09, pitch: 0, lowGain: -1.5, highGain: 1.5, wet: 16),
    ]

    @Published private(set) var presetId: String = "origin"

    var current: VoiceEffect {
        VoiceChangerStore.all.first { $0.id == presetId } ?? VoiceChangerStore.all[0]
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "chris.voiceEffect") ?? "origin"
        presetId = VoiceChangerStore.all.contains { $0.id == saved } ? saved : "origin"
    }

    func select(_ id: String) {
        guard VoiceChangerStore.all.contains(where: { $0.id == id }) else { return }
        presetId = id
        UserDefaults.standard.set(id, forKey: "chris.voiceEffect")

        TRTCBridge.shared.applyVoiceEffect()
    }
}

enum VoiceChanger {

    static func process(_ input: URL, preset: VoiceEffect) -> URL {
        guard preset.id != "origin" else { return input }
        do {
            let out = try render(input, preset)
            return out
        } catch {
            return input
        }
    }

    private static func render(_ input: URL, _ p: VoiceEffect) throws -> URL {
        let inFile = try AVAudioFile(forReading: input)
        let fmt = inFile.processingFormat
        let total = inFile.length
        guard total > 0, fmt.sampleRate > 0 else { return input }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let speed = AVAudioUnitVarispeed()
        let pitch = AVAudioUnitTimePitch()
        let eq = AVAudioUnitEQ(numberOfBands: 2)
        let reverb = AVAudioUnitReverb()

        speed.rate = p.speed
        pitch.rate = p.speed > 0 ? 1.0 / p.speed : 1.0
        pitch.pitch = p.pitch
        pitch.overlap = 8.0

        eq.bands[0].filterType = .lowShelf
        eq.bands[0].frequency = 200
        eq.bands[0].gain = p.lowGain
        eq.bands[0].bypass = (p.lowGain == 0)
        eq.bands[1].filterType = .highShelf
        eq.bands[1].frequency = 3200
        eq.bands[1].gain = p.highGain
        eq.bands[1].bypass = (p.highGain == 0)

        reverb.loadFactoryPreset(.mediumRoom)
        reverb.wetDryMix = p.wet

        engine.attach(player)
        engine.attach(speed)
        engine.attach(pitch)
        engine.attach(eq)
        engine.attach(reverb)
        engine.connect(player, to: speed, format: fmt)
        engine.connect(speed, to: pitch, format: fmt)
        engine.connect(pitch, to: eq, format: fmt)
        engine.connect(eq, to: reverb, format: fmt)
        engine.connect(reverb, to: engine.mainMixerNode, format: fmt)

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vfx-\(UUID().uuidString).m4a")
        let outSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: fmt.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let outFile = try AVAudioFile(forWriting: outURL, settings: outSettings)

        try engine.enableManualRenderingMode(.offline, format: fmt, maximumFrameCount: 4096)
        try engine.start()
        let maxFrames = engine.manualRenderingMaximumFrameCount

        var scheduled: AVAudioFramePosition = 0
        var lastBufferDone = false
        while scheduled < total {
            let want = AVAudioFrameCount(min(Int64(maxFrames), total - scheduled))
            guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: want) else { break }
            inFile.framePosition = scheduled
            try inFile.read(into: buf, frameCount: want)
            if buf.frameLength == 0 { break }
            scheduled += AVAudioFramePosition(buf.frameLength)
            player.scheduleBuffer(buf, completionCallbackType: .dataPlayedBack) { _ in
                lastBufferDone = true
            }
        }
        player.play()

        guard let renderBuf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                              frameCapacity: maxFrames) else {
            engine.stop()
            return input
        }

        let tailFrames = AVAudioFramePosition(fmt.sampleRate * 0.6)
        var rendered: AVAudioFramePosition = 0
        var spins = 0
        while true {
            let status = try engine.renderOffline(maxFrames, to: renderBuf)
            if status == .success {
                if renderBuf.frameLength == 0 { break }
                try outFile.write(from: renderBuf)
                rendered += AVAudioFramePosition(renderBuf.frameLength)
            }
            if lastBufferDone, rendered >= total + tailFrames { break }

            spins += 1
            if spins > 2000 { break }
        }
        engine.stop()
        player.stop()
        return outURL
    }
}

struct VoiceChangerView: View {
    @ObservedObject private var store = VoiceChangerStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("语音变声"), back: { dismiss() })
            ScrollView {
                VStack(spacing: 0) {
                    Text("发语音和打电话都会用这个声音。只做真人嗓（不做小孩音、电子音那种假声）：通话走实时变声，语音消息在你手机上处理完再发，原声不会上传。\n\n换嗓是把音高和共鸣腔一起调（等于换一个嗓门大小），所以听起来还是真人说话，只是像另一个人。")
                        .font(pf(13))
                        .foregroundColor(C.subLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    GroupCard {
                        ForEach(Array(VoiceChangerStore.all.enumerated()), id: \.element.id) { idx, e in
                            if idx > 0 { HairLine(inset: 16) }
                            Button { store.select(e.id) } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(e.name).font(pf(17)).foregroundColor(C.label)
                                        Text(e.hint).font(pf(12.5)).foregroundColor(C.subLabel)
                                    }
                                    Spacer(minLength: 8)
                                    if store.presetId == e.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(C.green)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 8)
                    Spacer().frame(height: 30)
                }
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
    }
}
