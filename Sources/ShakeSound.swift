import Foundation
import AVFoundation

@MainActor
final class ShakeSound {
    static let shared = ShakeSound()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let rate = 44100.0
    private var ready = false

    private init() { }

    private func prepare() {
        guard !ready else { return }
        let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: fmt)
        ready = true
    }

    func click() { play(makeClick()) }

    func ding() { play(makeDing()) }

    private func play(_ buf: AVAudioPCMBuffer?) {
        guard let buf = buf else { return }
        prepare()
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? s.setActive(true)
        if !engine.isRunning { try? engine.start() }
        player.stop()
        player.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
        player.play()
    }

    private func buffer(seconds: Double, fill: (Double) -> Double) -> AVAudioPCMBuffer? {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let n = AVAudioFrameCount(seconds * rate)
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n) else { return nil }
        buf.frameLength = n
        guard let ch = buf.floatChannelData?[0] else { return nil }
        for i in 0..<Int(n) {
            let t = Double(i) / rate
            ch[i] = Float(max(-1, min(1, fill(t))))
        }
        return buf
    }

    private func makeClick() -> AVAudioPCMBuffer? {
        var seed: UInt64 = 0x1234_5678
        func noise() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) & 0xFFFF) / 32768.0 - 1.0
        }
        return buffer(seconds: 0.09) { t in
            let env = exp(-t * 55)
            let body = sin(2 * .pi * 180 * t) * exp(-t * 80) * 0.35
            return (noise() * 0.55 + body) * env
        }
    }

    private func makeDing() -> AVAudioPCMBuffer? {
        buffer(seconds: 0.7) { t in
            let env = exp(-t * 4.2)
            let a = sin(2 * .pi * 1318.5 * t) * 0.5
            let b = sin(2 * .pi * 1975.5 * t) * 0.32
            let c = sin(2 * .pi * 2637.0 * t) * 0.16
            let attack = min(1, t / 0.006)
            return (a + b + c) * env * attack
        }
    }
}
