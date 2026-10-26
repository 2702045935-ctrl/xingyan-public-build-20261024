import SwiftUI
import UIKit
import AVFoundation
import CoreImage
import Vision

struct StickerFx: Identifiable, Hashable {
    var id: String
    var name: String
    var filter: String = ""

    var scale: Double = 0
    var face: String = ""

    var isFace: Bool { !face.isEmpty }
}

let stickerFxList: [StickerFx] = [
    StickerFx(id: "none", name: "无特效"),

    StickerFx(id: "ears",    name: "猫耳朵", face: "ears"),
    StickerFx(id: "bunny",   name: "兔耳朵", face: "bunny"),
    StickerFx(id: "crown",   name: "皇冠",   face: "crown"),
    StickerFx(id: "glasses", name: "墨镜",   face: "glasses"),
    StickerFx(id: "hearts",  name: "爱心眼", face: "hearts"),
    StickerFx(id: "blush",   name: "腮红",   face: "blush"),
    StickerFx(id: "puppy",   name: "小狗",   face: "puppy"),
    StickerFx(id: "sparkle", name: "闪光",   face: "sparkle"),

    StickerFx(id: "clear",  name: "清透", filter: "CIPhotoEffectProcess"),
    StickerFx(id: "mono",   name: "黑白", filter: "CIPhotoEffectMono"),
    StickerFx(id: "retro",  name: "复古", filter: "CIPhotoEffectInstant"),
    StickerFx(id: "comic",  name: "漫画", filter: "CIComicEffect"),
    StickerFx(id: "sepia",  name: "怀旧", filter: "CISepiaTone"),

    StickerFx(id: "pixel",     name: "像素",     filter: "CIPixellate",           scale: 12),
    StickerFx(id: "pixelBig",  name: "大像素",   filter: "CIPixellate",           scale: 30),
    StickerFx(id: "hexPixel",  name: "六边像素", filter: "CIHexagonalPixellate",  scale: 16),
    StickerFx(id: "dots",      name: "点彩",     filter: "CIPointillize",         scale: 10)
]

func stickerApply(_ img: CIImage, _ fx: StickerFx) -> CIImage {
    guard !fx.filter.isEmpty else { return img }
    if fx.scale > 0 {

        let key = (fx.filter == "CIPointillize") ? kCIInputRadiusKey : kCIInputScaleKey
        return img.applyingFilter(fx.filter, parameters: [key: fx.scale])
    }
    return img.applyingFilter(fx.filter)
}

let stickerEffectSource = "星言 Effect"

struct StickerFace: Equatable {

    var box: CGRect = CGRect(x: 0.25, y: 0.16, width: 0.5, height: 0.5)

    var leftEye: CGPoint = CGPoint(x: 0.40, y: 0.37)

    var rightEye: CGPoint = CGPoint(x: 0.60, y: 0.37)

    var nose: CGPoint = CGPoint(x: 0.50, y: 0.46)

    var mouth: CGPoint = CGPoint(x: 0.50, y: 0.56)

    var browY: CGFloat = 0.31

    var roll: CGFloat = 0

    var ok = false

    var eyeDist: CGFloat { max(0.02, hypot(rightEye.x - leftEye.x, rightEye.y - leftEye.y)) }

    var eyeMid: CGPoint { CGPoint(x: (leftEye.x + rightEye.x) / 2, y: (leftEye.y + rightEye.y) / 2) }

    static func estimated(_ b: CGRect) -> StickerFace {
        var f = StickerFace()
        f.box = b
        f.leftEye  = CGPoint(x: b.minX + b.width * 0.30, y: b.minY + b.height * 0.42)
        f.rightEye = CGPoint(x: b.minX + b.width * 0.70, y: b.minY + b.height * 0.42)
        f.nose     = CGPoint(x: b.midX,               y: b.minY + b.height * 0.58)
        f.mouth    = CGPoint(x: b.midX,               y: b.minY + b.height * 0.74)
        f.browY    = b.minY + b.height * 0.34
        f.roll     = 0
        f.ok = true
        return f
    }

    func mix(_ n: StickerFace, _ a: CGFloat) -> StickerFace {
        func lerp(_ x: CGPoint, _ y: CGPoint) -> CGPoint {
            CGPoint(x: x.x + (y.x - x.x) * a, y: x.y + (y.y - x.y) * a)
        }
        var o = self
        o.box = CGRect(x: box.minX + (n.box.minX - box.minX) * a,
                       y: box.minY + (n.box.minY - box.minY) * a,
                       width: box.width + (n.box.width - box.width) * a,
                       height: box.height + (n.box.height - box.height) * a)
        o.leftEye = lerp(leftEye, n.leftEye)
        o.rightEye = lerp(rightEye, n.rightEye)
        o.nose = lerp(nose, n.nose)
        o.mouth = lerp(mouth, n.mouth)
        o.browY = browY + (n.browY - browY) * a
        o.roll = roll + (n.roll - roll) * a
        o.ok = n.ok
        return o
    }
}

struct StickerShot {
    var base: UIImage
    var overlay: UIImage?
    var cropX: CGFloat
    var cropY: CGFloat
    var scale: CGFloat
}

final class StickerCam: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "sticker.cam.queue")
    private let ctx = CIContext(options: nil)

    @Published var frame: UIImage?

    @Published var denied = false

    var fxIndex = 0

    private var face = StickerFace()

    private var lastHit = Date.distantPast

    private let follow: CGFloat = 0.45

    private var detectEvery = 1

    @Published var faceOverlay: UIImage?

    private(set) var usingFront = true

    private var lastCI: CIImage?
    private var started = false
    private var rendering = false
    private var frameNo = 0

    private var fix: CGImagePropertyOrientation = .right

    private var missFrames = 0
    private var reportedMiss = false
    private var reportedHit = false

    func start() {
        guard !started else { return }
        started = true
        queue.async { [weak self] in self?.configure() }
    }

    func stop() {
        started = false
        queue.async { [weak self] in
            guard let s = self?.session else { return }
            if s.isRunning { s.stopRunning() }
        }
    }

    func flip() {
        usingFront.toggle()

        faceOverlay = nil
        queue.async { [weak self] in
            guard let self else { return }
            self.face = StickerFace()
            self.lastHit = Date.distantPast
            self.session.beginConfiguration()
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.commitConfiguration()
            self.configure()
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high
        let want: AVCaptureDevice.Position = usingFront ? .front : .back
        let pick = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: want)
        guard let dev = pick ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: dev),
              session.canAddInput(input) else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.denied = true }
            return
        }
        session.addInput(input)
        let out = AVCaptureVideoDataOutput()
        out.alwaysDiscardsLateVideoFrames = true
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        out.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(out) {
            session.addOutput(out)
            if let conn = out.connection(with: .video) {

                if #available(iOS 17.0, *) {
                    if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
                } else {
                    conn.videoOrientation = .portrait
                }
                if conn.isVideoMirroringSupported { conn.isVideoMirrored = (dev.position == .front) }
            }
        }
        session.commitConfiguration()
        session.startRunning()
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buf = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let raw = CIImage(cvPixelBuffer: buf)

        frameNo += 1
        var hit: (face: StickerFace, fix: CGImagePropertyOrientation)? = nil
        let runDetect = (frameNo % max(1, detectEvery) == 0)
        if runDetect {
            let t0 = CFAbsoluteTimeGetCurrent()
            hit = findFace(raw)
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            detectEvery = ms > 20 ? 2 : 1
        }
        if let hit {
            fix = hit.fix

            face = face.ok ? face.mix(hit.face, follow) : hit.face
            lastHit = Date()
            missFrames = 0
            if !reportedHit {
                reportedHit = true
                CrashCatcher.note("拍摄表情", "检到脸了 fix=\(hit.fix.rawValue) 眼距=\(String(format: "%.3f", face.eyeDist)) 歪头=\(String(format: "%.2f", face.roll))")
            }
        } else if runDetect {
            missFrames += 1

            if Date().timeIntervalSince(lastHit) > 0.6 { face.ok = false }
            if missFrames == 25, !reportedMiss {
                reportedMiss = true
                CrashCatcher.note("拍摄表情", "连续 25 次没检到脸（fix=\(fix.rawValue)，分辨率 \(Int(raw.extent.width))x\(Int(raw.extent.height))）")
            }
        }

        var img = oriented(raw, fix)
        let fx = stickerFxList[min(max(0, fxIndex), stickerFxList.count - 1)]
        img = stickerApply(img, fx)

        var over: UIImage? = nil
        if fx.isFace, face.ok {
            over = makeFaceOverlay(fx.face, frameSize: img.extent.size, face: face)
        }
        lastCI = img
        if let over {
            DispatchQueue.main.async { self.faceOverlay = over }
        } else if faceOverlay != nil {
            DispatchQueue.main.async { self.faceOverlay = nil }
        }
        guard !rendering else { return }
        rendering = true
        let ui = render(img)
        DispatchQueue.main.async {
            if let ui { self.frame = ui }
            self.rendering = false
        }
    }

    func snapshotParts() -> StickerShot? {
        guard let ci = lastCI else { return nil }
        let rect = cropRect(ci)
        let square = ci.cropped(to: rect)
            .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        guard let base = render(square) else { return nil }

        let cropY = ci.extent.height - rect.maxY
        let fx = stickerFxList[min(max(0, fxIndex), stickerFxList.count - 1)]
        guard fx.isFace, let over = faceOverlay, over.size.width > 1 else {
            return StickerShot(base: base, overlay: nil,
                               cropX: rect.minX, cropY: cropY, scale: 1)
        }
        return StickerShot(base: base, overlay: over,
                           cropX: rect.minX, cropY: cropY,
                           scale: max(0.01, ci.extent.width / over.size.width))
    }

    func applyOverlay(_ p: StickerShot, cut: UIImage) -> UIImage {
        guard let over = p.overlay else { return cut }
        let cropX = p.cropX
        let cropY = p.cropY
        let s = p.scale

        let r = UIGraphicsImageRenderer(size: cut.size)
        return r.image { c in
            cut.draw(in: CGRect(origin: .zero, size: cut.size))
            over.draw(in: CGRect(x: -cropX / s, y: -cropY / s,
                                 width: over.size.width / s, height: over.size.height / s))
        }
    }

    func snapshot() -> UIImage? {
        guard let p = snapshotParts() else { return nil }
        return applyOverlay(p, cut: p.base)
    }

    func faceOverlayForStill(_ img: UIImage, fx: StickerFx) -> UIImage? {
        guard fx.isFace, let ci = CIImage(image: img) else { return nil }
        guard let f = faceIn(ci) else { return nil }
        return makeFaceOverlay(fx.face, frameSize: ci.extent.size, face: f)
    }

    private func oriented(_ img: CIImage, _ o: CGImagePropertyOrientation) -> CIImage {
        o == .up ? img : img.oriented(o)
    }

    private func findFace(_ raw: CIImage) -> (face: StickerFace, fix: CGImagePropertyOrientation)? {
        var seen = Set<UInt32>()
        let all: [CGImagePropertyOrientation] = [fix, .up, .right, .left, .down].filter { o in
            if seen.contains(o.rawValue) { return false }
            seen.insert(o.rawValue)
            return true
        }

        let tries: [CGImagePropertyOrientation] = face.ok ? [fix] : all
        for o in tries {
            if let f = faceIn(oriented(raw, o)) { return (face: f, fix: o) }
        }
        return nil
    }

    private func faceIn(_ img: CIImage) -> StickerFace? {

        let e = img.extent
        let long = max(e.width, e.height)
        var probe = img
        if long > 900 { probe = img.transformed(by: CGAffineTransform(scaleX: 640 / long, y: 640 / long)) }
        let req = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(ciImage: probe, orientation: .up, options: [:])
        guard (try? handler.perform([req])) != nil, let list = req.results, !list.isEmpty else { return nil }

        guard let f = list.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) else { return nil }
        let b = f.boundingBox

        if b.width < 0.06 { return nil }
        var out = StickerFace.estimated(flipRect(b))

        if let lm = f.landmarks {
            if let p = lm.leftEye?.normalizedPoints, !p.isEmpty { out.leftEye = imagePoint(p, b) }
            if let p = lm.rightEye?.normalizedPoints, !p.isEmpty { out.rightEye = imagePoint(p, b) }
            if let p = lm.nose?.normalizedPoints, !p.isEmpty { out.nose = imagePoint(p, b) }
            if let p = lm.outerLips?.normalizedPoints, !p.isEmpty { out.mouth = imagePoint(p, b) }
            if let p = lm.leftEyebrow?.normalizedPoints, let q = lm.rightEyebrow?.normalizedPoints,
               !p.isEmpty, !q.isEmpty {
                out.browY = (imagePoint(p, b).y + imagePoint(q, b).y) / 2
            }
        }

        out.roll = atan2(out.rightEye.y - out.leftEye.y, out.rightEye.x - out.leftEye.x)
        return out
    }

    private func flipRect(_ b: CGRect) -> CGRect {
        CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
    }

    private func imagePoint(_ pts: [CGPoint], _ b: CGRect) -> CGPoint {
        var x: CGFloat = 0, y: CGFloat = 0
        for p in pts { x += p.x; y += p.y }
        let n = CGFloat(max(1, pts.count))
        return CGPoint(x: b.minX + (x / n) * b.width, y: 1 - (b.minY + (y / n) * b.height))
    }

    private func makeFaceOverlay(_ kind: String, frameSize: CGSize, face: StickerFace) -> UIImage? {
        guard frameSize.width > 1, frameSize.height > 1, face.ok else { return nil }
        let long = max(frameSize.width, frameSize.height)
        let s = min(1, 480 / long)
        let size = CGSize(width: frameSize.width * s, height: frameSize.height * s)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.opaque = false
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { c in
            drawStickerFace(kind, face, size, c.cgContext)
        }
    }

    func cutout(_ image: UIImage) -> UIImage {
        guard #available(iOS 17.0, *), let cg = image.cgImage else { return image }
        let req = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([req])) != nil,
              let res = req.results?.first,
              let mask = try? res.generateScaledMaskForImage(forInstances: res.allInstances, from: handler),
              let blend = CIFilter(name: "CIBlendWithMask") else { return image }
        let base = CIImage(cgImage: cg)
        blend.setValue(base, forKey: kCIInputImageKey)
        blend.setValue(CIImage(color: .white).cropped(to: base.extent),
                       forKey: kCIInputBackgroundImageKey)
        blend.setValue(CIImage(cvPixelBuffer: mask), forKey: kCIInputMaskImageKey)
        guard let out = blend.outputImage,
              let cgOut = ctx.createCGImage(out, from: out.extent) else { return image }
        return UIImage(cgImage: cgOut)
    }

    private func cropRect(_ img: CIImage) -> CGRect {
        let e = img.extent
        let side = min(e.width, e.height)
        var x = e.midX - side / 2
        var y = e.midY - side / 2
        if face.ok {
            let b = face.box
            let cx = e.minX + b.midX * e.width

            let cy = e.maxY - b.midY * e.height
            x = cx - side / 2
            y = cy - side / 2
        }
        x = min(max(e.minX, x), e.maxX - side)
        y = min(max(e.minY, y), e.maxY - side)
        return CGRect(x: x, y: y, width: side, height: side)
    }

    private func cropSquare(_ img: CIImage) -> CIImage {
        let rect = cropRect(img)
        return img.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
    }

    private func render(_ img: CIImage) -> UIImage? {
        guard let cg = ctx.createCGImage(img, from: img.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct StickerCamera: View {

    var onDone: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cam = StickerCam()

    @State private var fx = 0

    @State private var fxTab = 0
    @State private var shot: UIImage?
    @State private var busy = false
    @State private var flash = false

    @State private var showAlbum = false

    private var fxNow: StickerFx { stickerFxList[min(max(0, fx), stickerFxList.count - 1)] }

    var body: some View {

        GeometryReader { geo in
            let camW = min(geo.size.width - 96, 250)
            let camH = camW * 4 / 3

            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                HStack {
                    Button { cam.stop(); dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(Tr("拍摄表情"))
                        .font(pf(16, .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Color.clear.frame(width: 34, height: 34)
                }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)

                if shot == nil {
                    Text(Tr("表情将会上传保存，在其他设备也可查看"))
                        .font(pf(12.5))
                        .foregroundColor(.white.opacity(0.62))
                        .padding(.top, 6)
                }

                Spacer(minLength: 10)

                ZStack {
                    if let shot {
                        Image(uiImage: shot)
                            .resizable()
                            .scaledToFill()
                    } else if cam.denied {
                        VStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white.opacity(0.7))
                            Text(Tr("打不开相机，去系统设置里给星言开一下相机权限"))
                                .font(pf(12.5))
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 18)
                        }
                    } else {
                        StickerPreview(cam: cam)
                    }
                }
                .frame(width: camW, height: camH)
                .background(Color(white: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1))

                Spacer(minLength: 10)

                if shot == nil {
                    effectRow
                    shutterRow
                } else {
                    HStack(spacing: 12) {
                        Button { withAnimation(.easeOut(duration: 0.15)) { shot = nil } } label: {
                            Text(Tr("重拍"))
                                .font(pf(15, .medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Capsule().fill(Color.white.opacity(0.18)))
                        }
                        .buttonStyle(.plain)
                        Button {
                            if let s = shot { onDone(s) }
                            cam.stop()
                            dismiss()
                        } label: {
                            Text(Tr("使用"))
                                .font(pf(15, .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Capsule().fill(C.green))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 26)
                }
                }

                if flash {
                    Color.white.opacity(0.85).ignoresSafeArea()
                }
            }
        }
        .statusBarHidden(true)
        .onAppear { cam.start() }
        .onDisappear { cam.stop() }
        .sheet(isPresented: $showAlbum) {
            PhotoPicker { img in

                let sq = stickerSquare(img)
                let fxPick = fxNow
                DispatchQueue.global(qos: .userInitiated).async {
                    var out = stickerEffect(sq, fxPick)

                    if fxPick.isFace, let over = cam.faceOverlayForStill(sq, fx: fxPick) {
                        out = stickerCompose(out, over)
                    }
                    DispatchQueue.main.async { shot = out }
                }
            }
        }
    }

    private var effectRow: some View {
        VStack(spacing: 8) {

            HStack(spacing: 8) {
                tabChip(Tr("无特效"), 0)
                tabChip(Tr("特效"), 1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    let list = fxTab == 0 ? Array(stickerFxList.prefix(1)) : Array(stickerFxList.dropFirst())
                    ForEach(list) { item in
                        let i = stickerFxList.firstIndex(of: item) ?? 0
                        Button {
                            fx = i
                            cam.fxIndex = i
                        } label: {

                            VStack(spacing: 5) {
                                ZStack {
                                    Image(uiImage: StickerThumbs.shared.get(item))
                                        .resizable()
                                        .frame(width: 54, height: 54)
                                        .clipShape(Circle())
                                    Circle()
                                        .stroke(fx == i ? Color.white : Color.white.opacity(0.16),
                                                lineWidth: fx == i ? 2.4 : 1)
                                        .frame(width: 54, height: 54)
                                }
                                Text(Tr(item.name))
                                    .font(pf(11, fx == i ? .semibold : .regular))
                                    .foregroundColor(fx == i ? .white : .white.opacity(0.66))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }

            HStack(spacing: 6) {
                Text(Tr("特效来自：") + stickerEffectSource)
                    .font(pf(11.5))
                    .foregroundColor(.white.opacity(0.62))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 14)
    }

    private func tabChip(_ title: String, _ idx: Int) -> some View {
        Button {
            fxTab = idx
            if idx == 0 {
                fx = 0
                cam.fxIndex = 0
            } else if fx == 0 {
                fx = 1
                cam.fxIndex = 1
            }
        } label: {
            Text(title)
                .font(pf(12.5, fxTab == idx ? .semibold : .regular))
                .foregroundColor(fxTab == idx ? .white : .white.opacity(0.65))
                .padding(.horizontal, 11)
                .frame(height: 26)
                .background(Capsule().fill(fxTab == idx
                                           ? Color.white.opacity(0.28)
                                           : Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    private var shutterRow: some View {
        HStack(spacing: 0) {

            Button { showAlbum = true } label: {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.white.opacity(0.16)))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            Button { shoot() } label: {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.9), lineWidth: 4)
                        .frame(width: 74, height: 74)
                    Circle().fill(Color.white)
                        .frame(width: 58, height: 58)
                    if busy { ProgressView().tint(.black) }
                }
            }
            .buttonStyle(.plain)
            .disabled(busy)

            Button { cam.flip() } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.white.opacity(0.16)))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
        .padding(.bottom, 26)
    }

    private func shoot() {
        guard !busy, let parts = cam.snapshotParts() else { return }
        busy = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeOut(duration: 0.08)) { flash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeIn(duration: 0.12)) { flash = false }
        }

        CrashCatcher.note("拍摄表情", "快门：贴纸层=\(parts.overlay == nil ? "无" : "有")｜特效=\(fxNow.name)")
        DispatchQueue.global(qos: .userInitiated).async {

            let cut = cam.cutout(parts.base)
            let out = cam.applyOverlay(parts, cut: cut)
            DispatchQueue.main.async {
                shot = out
                busy = false
            }
        }
    }
}

private func stickerHeart(_ r: CGRect, _ g: CGContext) {
    let w = r.width, h = r.height
    let p = CGMutablePath()
    p.move(to: CGPoint(x: r.midX, y: r.maxY))
    p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.32),
               control1: CGPoint(x: r.midX - w * 0.58, y: r.maxY - h * 0.28),
               control2: CGPoint(x: r.minX, y: r.midY))
    p.addCurve(to: CGPoint(x: r.midX, y: r.minY + h * 0.30),
               control1: CGPoint(x: r.minX + w * 0.16, y: r.minY - h * 0.06),
               control2: CGPoint(x: r.midX - w * 0.18, y: r.minY))
    p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + h * 0.32),
               control1: CGPoint(x: r.midX + w * 0.18, y: r.minY),
               control2: CGPoint(x: r.maxX - w * 0.16, y: r.minY - h * 0.06))
    p.addCurve(to: CGPoint(x: r.midX, y: r.maxY),
               control1: CGPoint(x: r.maxX, y: r.midY),
               control2: CGPoint(x: r.midX + w * 0.58, y: r.maxY - h * 0.28))
    p.closeSubpath()
    g.addPath(p)
    g.fillPath()
}

private func stickerStar(_ c: CGPoint, _ r: CGFloat, _ g: CGContext) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: c.x, y: c.y - r))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + r * 0.18, y: c.y - r * 0.18))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + r * 0.18, y: c.y + r * 0.18))
    p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - r * 0.18, y: c.y + r * 0.18))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - r * 0.18, y: c.y - r * 0.18))
    p.closeSubpath()
    g.addPath(p)
    g.fillPath()
}

func drawStickerFace(_ kind: String, _ face: StickerFace, _ size: CGSize, _ g: CGContext) {
    let W = size.width, H = size.height
    guard W > 8, H > 8 else { return }

    let box = CGRect(x: face.box.minX * W, y: face.box.minY * H,
                     width: face.box.width * W, height: face.box.height * H)
    guard box.width > 6, box.height > 6 else { return }
    func px(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * W, y: p.y * H) }
    let le = px(face.leftEye)
    let re = px(face.rightEye)
    let nm = px(face.nose)
    let mid = CGPoint(x: (le.x + re.x) / 2, y: (le.y + re.y) / 2)
    let eyeD = max(6, hypot(re.x - le.x, re.y - le.y))
    let hw = box.width, hh = box.height

    func spun(_ pivot: CGPoint, _ body: () -> Void) {
        g.saveGState()
        g.translateBy(x: pivot.x, y: pivot.y)
        g.rotate(by: face.roll)
        g.translateBy(x: -pivot.x, y: -pivot.y)
        body()
        g.restoreGState()
    }

    g.saveGState()
    defer { g.restoreGState() }
    switch kind {
    case "ears":

        let ew = hw * 0.36, eh = hh * 0.40
        spun(mid) {
            for dx in [box.minX + hw * 0.02, box.maxX - hw * 0.02 - ew] {
                let base = box.minY + hh * 0.12
                let p = CGMutablePath()
                p.move(to: CGPoint(x: dx, y: base))
                p.addLine(to: CGPoint(x: dx + ew / 2, y: base - eh))
                p.addLine(to: CGPoint(x: dx + ew, y: base))
                p.closeSubpath()
                g.setFillColor(UIColor(red: 0.19, green: 0.17, blue: 0.21, alpha: 0.96).cgColor)
                g.addPath(p); g.fillPath()
                let q = CGMutablePath()
                q.move(to: CGPoint(x: dx + ew * 0.28, y: base - eh * 0.08))
                q.addLine(to: CGPoint(x: dx + ew / 2, y: base - eh * 0.74))
                q.addLine(to: CGPoint(x: dx + ew * 0.72, y: base - eh * 0.08))
                q.closeSubpath()
                g.setFillColor(UIColor(red: 1, green: 0.62, blue: 0.72, alpha: 0.95).cgColor)
                g.addPath(q); g.fillPath()
            }
        }
    case "bunny":

        let ew = hw * 0.22, eh = hh * 0.80
        spun(mid) {
            for dx in [box.minX + hw * 0.17, box.maxX - hw * 0.17 - ew] {
                let r = CGRect(x: dx, y: box.minY + hh * 0.20 - eh, width: ew, height: eh)
                g.setFillColor(UIColor(white: 0.98, alpha: 0.96).cgColor)
                g.fillEllipse(in: r)
                let inner = CGRect(x: r.minX + ew * 0.26, y: r.minY + eh * 0.12,
                                   width: ew * 0.48, height: eh * 0.74)
                g.setFillColor(UIColor(red: 1, green: 0.72, blue: 0.80, alpha: 0.92).cgColor)
                g.fillEllipse(in: inner)
            }
        }
    case "crown":

        let cw = eyeD * 3.1, ch = eyeD * 1.00
        let x = mid.x - cw / 2
        let y = box.minY - ch * 0.70
        spun(mid) {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: x, y: y + ch))
            p.addLine(to: CGPoint(x: x + cw * 0.12, y: y + ch * 0.22))
            p.addLine(to: CGPoint(x: x + cw * 0.30, y: y + ch * 0.78))
            p.addLine(to: CGPoint(x: x + cw * 0.50, y: y + ch * 0.14))
            p.addLine(to: CGPoint(x: x + cw * 0.70, y: y + ch * 0.78))
            p.addLine(to: CGPoint(x: x + cw * 0.88, y: y + ch * 0.22))
            p.addLine(to: CGPoint(x: x + cw, y: y + ch))
            p.closeSubpath()
            g.setFillColor(UIColor(red: 1.0, green: 0.80, blue: 0.20, alpha: 0.98).cgColor)
            g.addPath(p); g.fillPath()
            g.setFillColor(UIColor(red: 1, green: 1, blue: 1, alpha: 0.92).cgColor)
            for i in 0..<3 {
                let cx = x + cw * (0.14 + 0.36 * CGFloat(i))
                let d = max(3, eyeD * 0.16)
                g.fillEllipse(in: CGRect(x: cx - d / 2, y: y + ch * 0.82, width: d, height: d))
            }
        }
    case "glasses":

        let lw = eyeD * 1.20, lh = eyeD * 0.90
        spun(mid) {
            g.setFillColor(UIColor.black.withAlphaComponent(0.88).cgColor)
            for c in [le, re] {
                let r = CGRect(x: c.x - lw / 2, y: c.y - lh / 2, width: lw, height: lh)
                let lens = CGPath(roundedRect: r, cornerWidth: lh * 0.42,
                                  cornerHeight: lh * 0.42, transform: nil)
                g.addPath(lens); g.fillPath()
            }

            let bx = le.x + lw / 2 - lw * 0.10
            let bw = max(2, (re.x - lw / 2 + lw * 0.10) - bx)
            g.fill(CGRect(x: bx, y: mid.y - lh * 0.10, width: bw, height: lh * 0.20))

            g.setFillColor(UIColor.white.withAlphaComponent(0.26).cgColor)
            for c in [le, re] {
                g.fill(CGRect(x: c.x - lw * 0.34, y: c.y - lh * 0.24, width: lw * 0.36, height: lh * 0.16))
            }
        }
    case "hearts":

        let d = eyeD * 1.00
        spun(mid) {
            g.setFillColor(UIColor(red: 1, green: 0.24, blue: 0.36, alpha: 0.95).cgColor)
            for c in [le, re] {
                stickerHeart(CGRect(x: c.x - d / 2, y: c.y - d * 0.44, width: d, height: d), g)
            }
        }
    case "blush":

        let rw = eyeD * 1.00, rh = eyeD * 0.56
        spun(mid) {
            g.setFillColor(UIColor(red: 1, green: 0.45, blue: 0.55, alpha: 0.42).cgColor)
            for c in [le, re] {
                let cx = c.x + (c.x < mid.x ? -eyeD * 0.30 : eyeD * 0.30)
                g.fillEllipse(in: CGRect(x: cx - rw / 2, y: c.y + eyeD * 0.42, width: rw, height: rh))
            }
        }
    case "puppy":

        let ew = hw * 0.30, eh = hh * 0.56
        spun(mid) {
            g.setFillColor(UIColor(red: 0.45, green: 0.29, blue: 0.17, alpha: 0.95).cgColor)
            for dx in [box.minX - hw * 0.12, box.maxX - ew + hw * 0.12] {
                g.fillEllipse(in: CGRect(x: dx, y: box.minY + hh * 0.02, width: ew, height: eh))
            }
            let nd = eyeD * 0.58
            let nr = CGRect(x: nm.x - nd / 2, y: nm.y - nd * 0.60, width: nd, height: nd * 0.80)
            g.setFillColor(UIColor(red: 0.12, green: 0.10, blue: 0.11, alpha: 0.96).cgColor)
            let nose = CGPath(roundedRect: nr, cornerWidth: nd * 0.36,
                              cornerHeight: nd * 0.36, transform: nil)
            g.addPath(nose); g.fillPath()
        }
    case "sparkle":

        spun(mid) {
            g.setFillColor(UIColor(red: 1, green: 0.95, blue: 0.55, alpha: 0.95).cgColor)
            let spots: [(CGFloat, CGFloat, CGFloat)] = [
                (0.02, 0.10, 0.30), (0.92, 0.06, 0.34), (1.02, 0.52, 0.26),
                (-0.04, 0.46, 0.32), (0.16, -0.10, 0.24), (0.78, -0.08, 0.30)
            ]
            for sp in spots {
                stickerStar(CGPoint(x: box.minX + hw * sp.0, y: box.minY + hh * sp.1),
                            max(3, eyeD * sp.2), g)
            }
        }
    default:
        break
    }
}

func stickerFxThumb(_ item: StickerFx, _ side: CGFloat = 54) -> UIImage {
    let fmt = UIGraphicsImageRendererFormat.default()
    fmt.opaque = false
    fmt.scale = min(3, UIScreen.main.scale)
    let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt).image { c in
        let g = c.cgContext
        let r = CGRect(x: 0.5, y: 0.5, width: side - 1, height: side - 1)
        g.setFillColor(UIColor(white: 0.24, alpha: 1).cgColor)
        g.fillEllipse(in: r)

        let head = CGRect(x: side * 0.27, y: side * 0.22, width: side * 0.46, height: side * 0.60)
        g.setFillColor(UIColor(white: 0.93, alpha: 1).cgColor)
        g.fillEllipse(in: head)
        g.setFillColor(UIColor(white: 0.26, alpha: 1).cgColor)
        for ex in [head.minX + head.width * 0.31, head.minX + head.width * 0.69] {
            let d = side * 0.055
            g.fillEllipse(in: CGRect(x: ex - d / 2, y: head.minY + head.height * 0.44 - d / 2,
                                     width: d, height: d))
        }
        guard item.isFace else { return }
        g.saveGState()
        g.addEllipse(in: r)
        g.clip()
        drawStickerFace(item.face, StickerFace.estimated(head), CGSize(width: side, height: side), g)
        g.restoreGState()
    }

    return item.isFace ? img : stickerEffect(img, item)
}

final class StickerThumbs {
    static let shared = StickerThumbs()
    private var cache: [String: UIImage] = [:]
    func get(_ item: StickerFx) -> UIImage {
        if let c = cache[item.id] { return c }
        let img = stickerFxThumb(item)
        cache[item.id] = img
        return img
    }
}

func stickerSquare(_ img: UIImage) -> UIImage {
    guard let cg = img.cgImage else { return img }
    let w = CGFloat(cg.width), h = CGFloat(cg.height)
    let side = min(w, h)
    guard side > 0 else { return img }
    let rect = CGRect(x: (w - side) / 2, y: (h - side) / 2, width: side, height: side)
    guard let cropped = cg.cropping(to: rect) else { return img }
    return UIImage(cgImage: cropped, scale: img.scale, orientation: img.imageOrientation)
}

func stickerEffect(_ img: UIImage, _ fx: StickerFx) -> UIImage {
    guard !fx.filter.isEmpty, let ci = CIImage(image: img) else { return img }
    let out = stickerApply(ci, fx)
    let ctx = CIContext(options: nil)
    guard let cg = ctx.createCGImage(out, from: out.extent) else { return img }
    return UIImage(cgImage: cg, scale: img.scale, orientation: img.imageOrientation)
}

func stickerCompose(_ base: UIImage, _ over: UIImage) -> UIImage {
    let r = UIGraphicsImageRenderer(size: base.size)
    return r.image { c in
        base.draw(in: CGRect(origin: .zero, size: base.size))
        over.draw(in: CGRect(origin: .zero, size: base.size))
    }
}

private struct StickerPreview: View {
    @ObservedObject var cam: StickerCam
    var body: some View {
        GeometryReader { g in
            ZStack {
                if let f = cam.frame {
                    Image(uiImage: f)
                        .resizable()
                        .scaledToFill()
                        .frame(width: g.size.width, height: g.size.height)
                        .clipped()
                } else {
                    Color.black
                }

                if let o = cam.faceOverlay {
                    Image(uiImage: o)
                        .resizable()
                        .scaledToFill()
                        .frame(width: g.size.width, height: g.size.height)
                        .clipped()
                        .allowsHitTesting(false)
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}
