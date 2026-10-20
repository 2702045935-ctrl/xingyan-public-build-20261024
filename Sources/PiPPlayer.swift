import SwiftUI
import AVFoundation
import AVKit

final class PiPBox: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {

    @Published var supported = AVPictureInPictureController.isPictureInPictureSupported()

    @Published var possible = false

    @Published var active = false

    private var pip: AVPictureInPictureController?
    private var watch: NSKeyValueObservation?
    private weak var layer: AVPlayerLayer?

    func attach(_ layer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        if self.layer === layer, pip != nil { return }
        watch?.invalidate(); watch = nil
        pip?.delegate = nil
        self.layer = layer
        let c = AVPictureInPictureController(playerLayer: layer)
        c?.delegate = self
        pip = c
        watch = c?.observe(\.isPictureInPicturePossible, options: [.new, .initial]) { [weak self] obj, _ in
            let v = obj.isPictureInPicturePossible
            DispatchQueue.main.async { self?.possible = v }
        }
    }

    func toggle() {
        guard let c = pip else { return }
        if c.isPictureInPictureActive { c.stopPictureInPicture(); return }
        guard c.isPictureInPicturePossible else { return }

        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? s.setActive(true)
        c.startPictureInPicture()
    }

    func stop() { pip?.stopPictureInPicture() }

    func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) {
        DispatchQueue.main.async { self.active = true }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        DispatchQueue.main.async { self.active = false; self.possible = c.isPictureInPicturePossible }
    }

    func pictureInPictureController(_ c: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        DispatchQueue.main.async { self.active = false; self.possible = c.isPictureInPicturePossible }
    }
}

final class PiPLayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct PiPHostView: UIViewRepresentable {
    let player: AVPlayer?
    let box: PiPBox

    func makeUIView(context: Context) -> PiPLayerUIView {
        let v = PiPLayerUIView()
        v.backgroundColor = .black
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        box.attach(v.playerLayer)
        return v
    }

    func updateUIView(_ v: PiPLayerUIView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
        box.attach(v.playerLayer)
    }
}
