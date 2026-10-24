import Foundation
import AVFoundation
import Combine

@MainActor
final class Ringtone: ObservableObject {
    static let shared = Ringtone()

    enum Kind { case none, incoming, ringback }

    struct Tone: Identifiable, Hashable {
        let id: String
        let name: String
    }

    static let all: [Tone] = [
        Tone(id: "wechat", name: "默认"),
        Tone(id: "marimba", name: "马林巴"),
        Tone(id: "chime", name: "清脆"),
        Tone(id: "bubble", name: "气泡"),
        Tone(id: "pulse", name: "脉冲"),
        Tone(id: "classic", name: "经典电话"),
        Tone(id: "quiet", name: "轻柔")
    ]

    @Published private(set) var kind: Kind = .none
    @Published private(set) var previewing = ""
    @Published var current: String

    var currentName: String {
        Ringtone.all.first(where: { $0.id == current })?.name ?? "默认"
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let rate: Double = 44100
    private var previewTask: Task<Void, Never>?

    private init() {
        current = UserDefaults.standard.string(forKey: "chris.ringtone") ?? "wechat"
        let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: fmt)
    }

    func startIncoming() {
        if kind == .incoming, player.isPlaying { return }
        play(kind: .incoming)
    }

    func startRingback() {
        if kind == .ringback, player.isPlaying { return }
        play(kind: .ringback)
    }

    func stop() {
        previewTask?.cancel()
        previewTask = nil
        previewing = ""
        kind = .none
        player.stop()
        deactivate()
    }

    func preview(_ id: String) {
        stop()
        previewing = id
        activate()
        guard let buf = makeBuffer(melody(id)) else { return }
        player.stop()
        player.scheduleBuffer(buf, at: nil, options: .loops)
        if !engine.isRunning { try? engine.start() }
        player.play()
        previewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self = self, !Task.isCancelled else { return }
            if self.kind == .none { self.stop() }
        }
    }

    private func play(kind: Kind) {
        self.kind = kind
        previewTask?.cancel()
        previewing = ""
        activate()
        let timbre: Timbre = kind == .ringback ? .ringback : .melodic
        guard let buf = makeBuffer(kind == .ringback ? Ringtone.ringback : melody(current),
                                   timbre: timbre) else { return }
        player.stop()
        player.scheduleBuffer(buf, at: nil, options: .loops)
        if !engine.isRunning { try? engine.start() }
        player.play()
    }

    private func activate() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? s.setActive(true)
    }

    private func deactivate() {
        if engine.isRunning { engine.pause() }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private struct Note {
        let freq: Double
        let dur: Double
    }

    private enum Timbre: Equatable {
        case melodic
        case ringback
    }

    /// 外呼等待音：柔和的双音提示，保留电话等待感，但避免传统单频“嘟——”的生硬。
    private static let ringback: [Note] = [
        Note(freq: 392.00, dur: 0.56),
        Note(freq: 523.25, dur: 0.72),
        Note(freq: 0, dur: 2.52)
    ]

    private func melody(_ id: String) -> [Note] {
        switch id {
        case "marimba":
            return [.init(freq: 523, dur: 0.16), .init(freq: 659, dur: 0.16), .init(freq: 784, dur: 0.16),
                    .init(freq: 1046, dur: 0.30), .init(freq: 0, dur: 0.12),
                    .init(freq: 784, dur: 0.16), .init(freq: 1046, dur: 0.42), .init(freq: 0, dur: 0.5)]
        case "chime":
            return [.init(freq: 988, dur: 0.14), .init(freq: 1319, dur: 0.14), .init(freq: 1568, dur: 0.34),
                    .init(freq: 0, dur: 0.6)]
        case "bubble":
            return [.init(freq: 880, dur: 0.09), .init(freq: 0, dur: 0.05),
                    .init(freq: 1175, dur: 0.09), .init(freq: 0, dur: 0.05),
                    .init(freq: 880, dur: 0.09), .init(freq: 0, dur: 0.5)]
        case "pulse":
            return [.init(freq: 660, dur: 0.22), .init(freq: 0, dur: 0.10),
                    .init(freq: 660, dur: 0.22), .init(freq: 0, dur: 0.8)]
        case "classic":
            return [.init(freq: 440, dur: 0.4), .init(freq: 480, dur: 0.4), .init(freq: 0, dur: 1.4)]
        case "quiet":
            return [.init(freq: 587, dur: 0.5), .init(freq: 0, dur: 0.3), .init(freq: 494, dur: 0.6), .init(freq: 0, dur: 1.4)]
        default:
            return [.init(freq: 659, dur: 0.16), .init(freq: 784, dur: 0.16), .init(freq: 988, dur: 0.16),
                    .init(freq: 1319, dur: 0.34), .init(freq: 0, dur: 0.18),
                    .init(freq: 988, dur: 0.16), .init(freq: 1175, dur: 0.16),
                    .init(freq: 1319, dur: 0.42), .init(freq: 0, dur: 0.6)]
        }
    }

    private func makeBuffer(_ notes: [Note], timbre: Timbre = .melodic) -> AVAudioPCMBuffer? {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let total = notes.reduce(0.0) { $0 + $1.dur }
        let frames = AVAudioFrameCount(max(1, total * rate))
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames),
              let ptr = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = frames
        var i = 0
        for n in notes {
            let count = Int(n.dur * rate)
            for k in 0..<count where i < Int(frames) {
                let t = Double(k) / rate
                var v = 0.0
                if n.freq > 0 {
                    let attack = timbre == .ringback ? 0.045 : 0.012
                    let release = timbre == .ringback ? min(0.28, n.dur * 0.48) : 0.06
                    let env = min(1, min(t / attack, max(0, (n.dur - t) / release)))
                    let base = sin(2 * .pi * n.freq * t)
                    let second = sin(4 * .pi * n.freq * t)
                    if timbre == .ringback {
                        let third = sin(6 * .pi * n.freq * t)
                        let breath = 0.97 + 0.03 * sin(2 * .pi * 2.1 * t)
                        v = (base * 0.58 + second * 0.12 + third * 0.035) * env * breath
                    } else {
                        v = (base * 0.62 + second * 0.2) * env
                    }
                }
                ptr[i] = Float(v * (timbre == .ringback ? 0.36 : 0.55))
                i += 1
            }
        }
        return buf
    }
}
