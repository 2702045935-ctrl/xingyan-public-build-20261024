import Foundation
import UIKit
import CoreImage
import Vision
import AVFoundation
import WebRTC
import TXLiteAVSDK_TRTC

final class VideoBlur: NSObject, TRTCVideoFrameDelegate {
    static let shared = VideoBlur()

    var enabled = false

    var onAutoOff: ((String) -> Void)?

    private let ctx = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()
    private var mask: CVPixelBuffer?
    private var maskSize = CGSize.zero
    private var tick = 0
    private var slowFrames = 0

    func reset() {
        lock.lock()
        mask = nil
        maskSize = .zero
        tick = 0
        slowFrames = 0
        lock.unlock()
    }

    func process(_ src: CVPixelBuffer) -> CVPixelBuffer? {
        guard enabled else { return nil }
        let t0 = CFAbsoluteTimeGetCurrent()
        let w = CVPixelBufferGetWidth(src)
        let h = CVPixelBufferGetHeight(src)
        guard w > 1, h > 1 else { return nil }
        let ext = CGRect(x: 0, y: 0, width: w, height: h)

        lock.lock()
        if mask == nil || tick % 3 == 0 {
            mask = personMask(src)
            maskSize = ext.size
        }
        tick &+= 1
        let m = mask
        lock.unlock()
        guard let m = m else { return nil }

        let ci = CIImage(cvPixelBuffer: src)

        guard let blur = CIFilter(name: "CIGaussianBlur") else { return nil }
        let half = ci.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
        blur.setValue(half.clampedToExtent(), forKey: kCIInputImageKey)
        blur.setValue(18.0, forKey: kCIInputRadiusKey)
        guard let blurredHalf = blur.outputImage else { return nil }
        let blurred = blurredHalf
            .cropped(to: CGRect(x: 0, y: 0, width: CGFloat(w) / 2, height: CGFloat(h) / 2))
            .transformed(by: CGAffineTransform(scaleX: 2, y: 2))
            .cropped(to: ext)

        let maskCI = CIImage(cvPixelBuffer: m)
        let me = maskCI.extent
        guard me.width > 1, me.height > 1 else { return nil }
        let scaled = maskCI.transformed(by: CGAffineTransform(scaleX: ext.width / me.width,
                                                              y: ext.height / me.height))

        guard let blend = CIFilter(name: "CIBlendWithMask") else { return nil }
        blend.setValue(ci, forKey: kCIInputImageKey)
        blend.setValue(blurred, forKey: kCIInputBackgroundImageKey)
        blend.setValue(scaled, forKey: kCIInputMaskImageKey)
        guard let out = blend.outputImage, let dst = makeBuffer(w: w, h: h) else { return nil }
        ctx.render(out, to: dst, bounds: ext, colorSpace: CGColorSpaceCreateDeviceRGB())

        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        lock.lock()
        slowFrames = ms > 45 ? slowFrames + 1 : 0
        let tooSlow = slowFrames > 12
        lock.unlock()
        if tooSlow {
            enabled = false
            reset()
            onAutoOff?("手机有点吃力，模糊背景已自动关闭")
        }
        return dst
    }

    private func personMask(_ src: CVPixelBuffer) -> CVPixelBuffer? {
        let req = VNGeneratePersonSegmentationRequest()
        req.qualityLevel = .fast
        req.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let handler = VNImageRequestHandler(cvPixelBuffer: src, orientation: .up, options: [:])
        do { try handler.perform([req]) } catch { return nil }
        return req.results?.first?.pixelBuffer
    }

    private func makeBuffer(w: Int, h: Int) -> CVPixelBuffer? {
        let attrs: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        var buf: CVPixelBuffer?
        let r = CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA,
                                    attrs as CFDictionary, &buf)
        return r == kCVReturnSuccess ? buf : nil
    }

    func onProcessVideoFrame(_ srcFrame: TRTCVideoFrame, dstFrame: TRTCVideoFrame) -> UInt32 {
        guard enabled, let src = srcFrame.pixelBuffer, let out = process(src) else { return 0 }
        dstFrame.pixelBuffer = out
        return 0
    }
}

final class BlurCapturer: NSObject, RTCVideoCapturerDelegate {
    private let inner: RTCVideoCapturerDelegate

    init(inner: RTCVideoCapturerDelegate) {
        self.inner = inner
        super.init()
    }

    func capturer(_ capturer: RTCVideoCapturer, didCapture frame: RTCVideoFrame) {
        guard VideoBlur.shared.enabled,
              let buf = frame.buffer as? RTCCVPixelBuffer,
              let out = VideoBlur.shared.process(buf.pixelBuffer) else {
            inner.capturer(capturer, didCapture: frame)
            return
        }
        let nb = RTCCVPixelBuffer(pixelBuffer: out)
        let nf = RTCVideoFrame(buffer: nb, rotation: frame.rotation, timeStampNs: frame.timeStampNs)
        inner.capturer(capturer, didCapture: nf)
    }
}
