import Foundation
import AVFoundation

@MainActor
final class KeepAlive {
    static let shared = KeepAlive()
    private init() {}

    private var player: AVAudioPlayer?
    private(set) var running = false

    private static func silentWavData(seconds: Int = 1, sampleRate: Int = 8000) -> Data {
        let dataBytes = seconds * sampleRate * 2
        var d = Data()
        func le32(_ v: Int) -> Data { var x = UInt32(v).littleEndian; return Data(bytes: &x, count: 4) }
        func le16(_ v: Int) -> Data { var x = UInt16(v).littleEndian; return Data(bytes: &x, count: 2) }
        d.append("RIFF".data(using: .ascii)!)
        d.append(le32(36 + dataBytes))
        d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!)
        d.append(le32(16))
        d.append(le16(1))
        d.append(le16(1))
        d.append(le32(sampleRate))
        d.append(le32(sampleRate * 2))
        d.append(le16(2))
        d.append(le16(16))
        d.append("data".data(using: .ascii)!)
        d.append(le32(dataBytes))
        d.append(Data(count: dataBytes))
        return d
    }

    func start() {
        guard !running else { return }

        if CallCenter.shared.phase.isBusy { return }
        guard !API.shared.token.isEmpty else { return }
        do {
            let session = AVAudioSession.sharedInstance()

            if MusicPlayer.shared.current == nil {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            }
            try session.setActive(true)
            let p = try AVAudioPlayer(data: Self.silentWavData())
            p.numberOfLoops = -1
            p.volume = 0
            p.prepareToPlay()
            p.play()
            player = p
            running = true
            Realtime.shared.start()
        } catch {
            running = false
        }
    }

    func stop() {
        guard running || player != nil else { return }
        player?.stop()
        player = nil
        running = false

        if MusicPlayer.shared.current != nil { return }
        if !CallCenter.shared.phase.isBusy {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }
}
