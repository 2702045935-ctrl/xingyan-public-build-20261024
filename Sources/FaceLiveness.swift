import SwiftUI
import AVFoundation
import Vision
import UIKit

struct FaceVerifyFlowView: View {

    let onDone: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var step = 0

    var body: some View {
        if step == 0 {
            FacePrepView(
                onStart: { withAnimation(.easeOut(duration: 0.2)) { step = 1 } },
                onCancel: { onDone(false); dismiss() }
            )
        } else {
            FaceLivenessView { ok in onDone(ok) }
                .transition(.move(edge: .trailing))
        }
    }
}

struct FacePrepView: View {
    var onStart: () -> Void
    var onCancel: () -> Void

    private let green = C.green

    private let tips: [(String, String)] = [
        ("light.max", "找个光线亮一点的地方"),
        ("eyeglasses", "摘下眼镜、口罩、帽子"),
        ("person.crop.circle", "把整张脸放进圆框里，别挡住"),
        ("hand.raised.fill", "跟着提示做几个动作：眨眼 / 张嘴 / 摇头 / 点头"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("人脸识别"), back: { onCancel() })

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {

                    ZStack {
                        Circle().stroke(green.opacity(0.18), lineWidth: 6).frame(width: 168, height: 168)
                        Circle().fill(green.opacity(0.10)).frame(width: 150, height: 150)
                        Image(systemName: "faceid")
                            .font(.system(size: 72, weight: .light))
                            .foregroundColor(green)
                    }
                    .padding(.top, 22)

                    VStack(spacing: 6) {
                        Text(Tr("请本人操作")).font(pf(19, .semibold)).foregroundColor(C.label)
                        Text(Tr("为了确认是你本人，接下来会请你做几个动作"))
                            .font(pf(13.5)).foregroundColor(C.subLabel)
                            .multilineTextAlignment(.center).padding(.horizontal, 26)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(tips.enumerated()), id: \.offset) { i, t in
                            HStack(spacing: 12) {
                                Image(systemName: t.0)
                                    .font(.system(size: 15))
                                    .foregroundColor(green)
                                    .frame(width: 26)
                                Text(Tr(t.1)).font(pf(14.5)).foregroundColor(C.label)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 50)
                            if i < tips.count - 1 { HairLine(inset: 54) }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(C.cardBg))
                    .padding(.horizontal, 14)

                    Text(Tr("人脸信息只在这台手机的摄像头里做判定，不会上传、也不会保存。\n整个过程大概 10 秒。"))
                        .font(pf(12.5)).foregroundColor(C.subLabel)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    Spacer().frame(height: 6)
                }
            }
            .background(C.pageBg)

            Button { onStart() } label: {
                Text(Tr("开始识别"))
                    .font(pf(17, .medium)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(green))
                    .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .padding(.bottom, max(12, L.safeBottom * 0.6))
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { onCancel() }
    }
}

enum FaceAction: CaseIterable {
    case blink
    case mouth
    case shake
    case nod

    var title: String {
        switch self {
        case .blink: return "请眨眨眼"
        case .mouth: return "请张张嘴"
        case .shake: return "请摇摇头"
        case .nod:   return "请点点头"
        }
    }
    var hint: String {
        switch self {
        case .blink: return "慢慢眨一次眼，别挡住眼睛"
        case .mouth: return "嘴张开一点点就行"
        case .shake: return "头往左转一下、再往右转一下（幅度要看得出来）"
        case .nod:   return "头往下低一下、再抬起来（别只是往前凑）"
        }
    }
    var icon: String {
        switch self {
        case .blink: return "eye"
        case .mouth: return "mouth"
        case .shake: return "arrow.left.and.right"
        case .nod:   return "arrow.up.and.down"
        }
    }
}

struct FaceLivenessView: View {

    let onDone: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var plan: [FaceAction] = []
    @State private var idx = 0
    @State private var hasFace = false
    @State private var tooMany = false
    @State private var tooFar = false
    @State private var hint = ""

    @State private var stall = 0
    @State private var done = false

    @State private var lightLuma = 0.5
    @State private var lightContrast = 0.2

    private let green = C.green

    private var cur: FaceAction? { idx < plan.count ? plan[idx] : nil }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("人脸识别"), back: {
                FaceLiveness.shared.stop()
                onDone(false)
                dismiss()
            })

            Spacer(minLength: 8)

            ZStack {
                Circle().fill(Color.black.opacity(0.88))
                FaceCameraPreview()
                    .clipShape(Circle())
                    .padding(3)
                    .opacity(hasFace && !tooMany ? 1 : 0.5)
                Circle().stroke(green.opacity(0.22), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.35), value: progress)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.25), radius: 8)
                } else if let a = cur {
                    Image(systemName: a.icon)
                        .font(.system(size: 30, weight: .light))
                        .foregroundColor(.white.opacity(hasFace ? 0.95 : 0.5))
                        .offset(y: 96)
                }
            }
            .frame(width: 262, height: 262)

            Text(Tr(title))
                .font(pf(18, .medium))
                .foregroundColor(C.label)
                .padding(.top, 22)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            Text(Tr(subTitle))
                .font(pf(13))
                .foregroundColor(C.subLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 8)

            HStack(spacing: 10) {
                ForEach(Array(plan.enumerated()), id: \.offset) { i, a in
                    Image(systemName: i < idx ? "checkmark.circle.fill" : a.icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(i < idx ? green : C.subLabel.opacity(0.5))
                }
            }
            .padding(.top, 16)

            Spacer(minLength: 16)

            Text(Tr("人脸信息只在这台手机的摄像头里做判定，不会上传也不会保存。"))
                .font(pf(12))
                .foregroundColor(C.subLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.bottom, 24)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack {
            FaceLiveness.shared.stop()
            onDone(false)
            dismiss()
        }
        .onAppear {
            if plan.isEmpty {

                let others = FaceAction.allCases.filter { $0 != .blink }.shuffled()
                plan = [.blink] + others.prefix(2)
            }
            stall = 0
            FaceLiveness.shared.start { ev in
                DispatchQueue.main.async { handle(ev) }
            }
        }
        .onDisappear { FaceLiveness.shared.stop() }
    }

    private var title: String {
        if done { return "验证通过" }
        if tooMany { return "画面里只能有一个人" }
        if !hasFace { return "请把脸放进圆框里" }
        if tooFar { return "靠近一点" }
        if lightLuma < 0.16 { return "这里太暗了" }
        if lightLuma > 0.90 { return "这里太亮了" }
        return cur?.title ?? "请正对屏幕"
    }

    private var subTitle: String {
        if done { return "" }
        if tooMany { return "把旁边的人移出画面，或者找一个安静的地方" }
        if !hasFace { return "光线亮一点、别挡住脸" }
        if tooFar { return "脸再靠近一点，占满中间这个框" }
        if lightLuma < 0.16 { return "找个亮一点的地方，别背光" }
        if lightLuma > 0.90 { return "光太强了：别对着灯或太阳，稍微挪一下" }
        if !FaceLiveness.shared.depthReady, lightContrast < 0.035 {
            return "画面太平了（像照片 / 屏幕）：请用**真人脸**、别对着屏幕或照片"
        }
        if !hint.isEmpty { return hint }
        return cur?.hint ?? ""
    }

    private var progress: CGFloat {
        guard !plan.isEmpty else { return 0.04 }
        if done { return 1 }
        return max(0.04, CGFloat(idx) / CGFloat(plan.count))
    }

    private func handle(_ ev: FaceLiveness.Event) {
        switch ev {
        case .noFace:
            hasFace = false
            tooFar = false
        case .multi:
            tooMany = true
        case .face(let h, let luma, let contrast):
            tooMany = false
            hasFace = true
            tooFar = h < 0.30
            lightLuma = luma
            lightContrast = contrast
        case .blink:
            if cur == .blink, hasFace, !tooFar { advance() }
        case .mouth:
            if cur == .mouth, hasFace, !tooFar { advance() }

        case .shake:
            if cur == .shake, hasFace, !tooFar { advance() }
        case .nod:
            if cur == .nod, hasFace, !tooFar { advance() }
        case .tick:

            guard hasFace, !tooMany, !done else { return }
            stall += 1
            if stall == 4 { hint = "没看清，再来一次" }
            if stall >= 12 {
                resetStep()
                hint = "这次没看清：照着提示再做一次"
            }
        }
    }

    private func advance() {

        if FaceLiveness.shared.depthReady, let r = FaceLiveness.shared.depthRangeValue,
           r < 0.030, idx >= plan.count - 1 {
            hint = "看着像平面（照片 / 屏幕 / 生成的图）：请用**真人脸**、别对着屏幕或照片"
            stall = 6
            return
        }

        if idx >= plan.count - 1 {
            if lightLuma < 0.16 || lightLuma > 0.90 {
                hint = "光线不合适：换个亮一点（或别太晃眼）的地方再来一次"
                stall = 6
                return
            }
            if !FaceLiveness.shared.depthReady, lightContrast < 0.035 {
                hint = "画面太平（像照片 / 屏幕）：请用真人脸，别对着屏幕或照片"
                stall = 6
                return
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        idx += 1
        resetStep()
        if idx >= plan.count {
            done = true
            FaceLiveness.shared.stop()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                onDone(true)
                dismiss()
            }
        }
    }

    private func resetStep() {
        stall = 0
        hint = ""
    }
}

final class FaceLiveness: NSObject {
    static let shared = FaceLiveness()

    enum Event {
        case noFace
        case multi

        case face(CGFloat, Double, Double)
        case blink
        case mouth

        case shake

        case nod

        case tick
    }

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "chris.face.liveness")
    private var onEvent: ((Event) -> Void)?
    private var running = false
    private var lastFaceAt = Date()
    private var lastTick = Date()
    private var lastBlinkAt = Date.distantPast
    private var lastMouthAt = Date.distantPast
    private var lastMultiAt = Date.distantPast

    private var earSamples: [CGFloat] = []
    private var earClosed = false

    private var mouthFrames = 0

    private var yawHist: [(t: Date, v: Double)] = []
    private var pitchHist: [(t: Date, v: Double)] = []

    private var sizeHist: [(t: Date, v: Double)] = []

    private var baseHist: [Double] = []
    private var pitchBase: Double = 0
    private var lastShakeAt = Date.distantPast
    private var lastNodAt = Date.distantPast

    var shot: String? = nil
    private let ci = CIContext()

    private(set) var depthReady = false

    private(set) var depthRangeValue: Double? = nil

    var captureSession: AVCaptureSession { session }

    func start(onEvent: @escaping (Event) -> Void) {
        self.onEvent = onEvent
        shot = nil
        depthRangeValue = nil
        guard !running else { return }
        running = true
        queue.async { [weak self] in
            guard let self = self else { return }

            self.resetJudgement()
            self.session.beginConfiguration()
            self.session.sessionPreset = .high
            if self.session.inputs.isEmpty,
               let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video),
               let input = try? AVCaptureDeviceInput(device: dev),
               self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            let out = AVCaptureVideoDataOutput()
            out.alwaysDiscardsLateVideoFrames = true
            out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            out.setSampleBufferDelegate(self, queue: self.queue)
            if self.session.outputs.isEmpty, self.session.canAddOutput(out) {
                self.session.addOutput(out)
            }

            if self.session.outputs.count < 2 {
                let dOut = AVCaptureDepthDataOutput()
                dOut.isFilteringEnabled = true
                dOut.setDelegate(self, callbackQueue: self.queue)
                if let dev = (self.session.inputs.first as? AVCaptureDeviceInput)?.device,
                   dev.activeFormat.supportedDepthDataFormats.count > 0,
                   self.session.canAddOutput(dOut) {
                    self.session.addOutput(dOut)
                    if let f = dev.activeFormat.supportedDepthDataFormats.last,
                       (dev.activeFormat.supportedDepthDataFormats.contains { $0 === dev.activeDepthDataFormat }) == false {
                        try? dev.lockForConfiguration()
                        dev.activeDepthDataFormat = f
                        dev.unlockForConfiguration()
                    }
                    self.depthReady = true
                }
            }
            self.session.commitConfiguration()
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        onEvent = nil
        guard running else { return }
        running = false
        queue.async { [weak self] in
            guard let self = self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func emit(_ ev: Event) { onEvent?(ev) }

    private func resetJudgement() {
        yawHist.removeAll()
        pitchHist.removeAll()
        sizeHist.removeAll()
        baseHist.removeAll()
        pitchBase = 0
        lastShakeAt = Date.distantPast
        lastNodAt = Date.distantPast
        earSamples.removeAll()
        earClosed = false
        mouthFrames = 0
    }

    private func eyeRatios(_ obs: VNFaceObservation) -> (left: CGFloat?, right: CGFloat?) {
        func ratio(_ r: VNFaceLandmarkRegion2D?) -> CGFloat? {
            guard let r, r.pointCount > 4 else { return nil }
            let pts = r.normalizedPoints
            let xs = pts.map { CGFloat($0.x) }, ys = pts.map { CGFloat($0.y) }
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { return nil }
            let w = maxX - minX
            guard w > 0.0001 else { return nil }
            return (maxY - minY) / w
        }
        guard let lm = obs.landmarks else { return (nil, nil) }
        return (ratio(lm.leftEye), ratio(lm.rightEye))
    }

    private func mouthOpen(_ obs: VNFaceObservation) -> CGFloat? {
        guard let lm = obs.landmarks, let m = (lm.innerLips ?? lm.outerLips), m.pointCount > 3 else { return nil }
        let pts = m.normalizedPoints
        let xs = pts.map { CGFloat($0.x) }, ys = pts.map { CGFloat($0.y) }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        let w = maxX - minX
        guard w > 0.0001 else { return nil }
        return (maxY - minY) / w
    }

    private func lightQuality(_ pb: CVPixelBuffer, box: CGRect) -> (luma: Double, contrast: Double) {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return (0.5, 0.2) }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        let bpr = CVPixelBufferGetBytesPerRow(pb)

        let x0 = max(0, Int(Double(w) * Double(box.minX + box.width * 0.25)))
        let x1 = min(w, Int(Double(w) * Double(box.minX + box.width * 0.75)))
        let y0 = max(0, Int(Double(h) * (1 - Double(box.minY + box.height * 0.75))))
        let y1 = min(h, Int(Double(h) * (1 - Double(box.minY + box.height * 0.25))))
        guard x1 > x0 + 8, y1 > y0 + 8 else { return (0.5, 0.2) }
        var sum = 0.0, sum2 = 0.0, n = 0.0
        var y = y0
        while y < y1 {
            let row = base.advanced(by: y * bpr).assumingMemoryBound(to: UInt8.self)
            var x = x0
            while x < x1 {
                let b = Double(row[x * 4]), g = Double(row[x * 4 + 1]), r = Double(row[x * 4 + 2])
                let l = (0.114 * b + 0.587 * g + 0.299 * r) / 255.0
                sum += l; sum2 += l * l; n += 1
                x += 3
            }
            y += 3
        }
        guard n > 20 else { return (0.5, 0.2) }
        let mean = sum / n
        return (mean, max(0, sum2 / n - mean * mean).squareRoot())
    }

    private func poseProxy(_ obs: VNFaceObservation) -> (yaw: Double, pitch: Double)? {
        guard let lm = obs.landmarks,
              let nose = lm.nose, nose.pointCount > 0,
              let le = lm.leftEye, le.pointCount > 0,
              let re = lm.rightEye, re.pointCount > 0 else { return nil }
        let b = obs.boundingBox

        func mid(_ r: VNFaceLandmarkRegion2D) -> CGPoint {
            let pts = r.normalizedPoints
            let x = pts.reduce(0.0) { $0 + Double($1.x) } / Double(max(1, pts.count))
            let y = pts.reduce(0.0) { $0 + Double($1.y) } / Double(max(1, pts.count))
            return CGPoint(x: b.minX + CGFloat(x) * b.width, y: b.minY + CGFloat(y) * b.height)
        }
        let lc = mid(le), rc = mid(re), nc = mid(nose)
        let dx = Double(rc.x - lc.x), dy = Double(rc.y - lc.y)
        let eyeDist = max(0.001, (dx * dx + dy * dy).squareRoot())

        let roll = atan2(dy, dx)
        let cr = cos(-roll), sr = sin(-roll)
        let ex = Double(lc.x + rc.x) / 2, ey = Double(lc.y + rc.y) / 2
        func upright(_ p: CGPoint) -> (x: Double, y: Double) {
            let vx = Double(p.x) - ex, vy = Double(p.y) - ey
            return (vx * cr - vy * sr, vx * sr + vy * cr)
        }
        let n = upright(nc)
        return (yaw: n.x / eyeDist, pitch: -n.y / eyeDist)
    }

    private func trackPose(yaw: Double, pitch: Double, size: Double, now: Date) {

        yawHist.append((now, yaw))
        while let f = yawHist.first, now.timeIntervalSince(f.t) > 1.6 { yawHist.removeFirst() }
        if yawHist.count > 150 { yawHist.removeFirst() }
        let yRight = yawHist.filter { $0.v > 0.09 }.count
        let yLeft = yawHist.filter { $0.v < -0.09 }.count
        if yRight >= 2, yLeft >= 2, now.timeIntervalSince(lastShakeAt) > 1.0 {
            lastShakeAt = now
            yawHist.removeAll()
            emit(.shake)
        }

        if baseHist.count < 60 { baseHist.append(pitch) } else { baseHist.removeFirst(); baseHist.append(pitch) }
        let sorted = baseHist.sorted()
        if !sorted.isEmpty { pitchBase = sorted[sorted.count / 2] }
        let p = pitch - pitchBase
        pitchHist.append((now, p))
        sizeHist.append((now, size))
        while let f = pitchHist.first, now.timeIntervalSince(f.t) > 2.2 { pitchHist.removeFirst() }
        while let f = sizeHist.first, now.timeIntervalSince(f.t) > 2.2 { sizeHist.removeFirst() }
        if pitchHist.count > 200 { pitchHist.removeFirst() }
        if sizeHist.count > 200 { sizeHist.removeFirst() }
        let pDown = pitchHist.filter { $0.v > 0.038 }.count
        let pUp = pitchHist.filter { $0.v < -0.038 }.count

        let sizes = sizeHist.map { $0.v }
        let sMin = sizes.min() ?? 0, sMax = sizes.max() ?? 0
        let steady = sMin > 0.001 && (sMax - sMin) / sMin < 0.12
        if pDown >= 2, pUp >= 2, steady, now.timeIntervalSince(lastNodAt) > 1.0 {
            lastNodAt = now
            pitchHist.removeAll()
            sizeHist.removeAll()
            emit(.nod)
        }
    }
}

extension FaceLiveness: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard running, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let req = VNDetectFaceLandmarksRequest()

        let handler = VNImageRequestHandler(cvPixelBuffer: pb, orientation: .leftMirrored, options: [:])
        try? handler.perform([req])
        let faces = (req.results ?? []).filter { $0.confidence > 0.4 }
        let now = Date()

        if faces.count > 1 {
            if now.timeIntervalSince(lastMultiAt) > 0.5 {
                lastMultiAt = now
                emit(.multi)
            }
            return
        }

        if let f = faces.first {
            lastFaceAt = now

            let q = lightQuality(pb, box: f.boundingBox)
            emit(.face(CGFloat(f.boundingBox.height), q.luma, q.contrast))

            if shot == nil {
                let image = CIImage(cvPixelBuffer: pb)
                if let cg = ci.createCGImage(image, from: image.extent) {
                    let ui = UIImage(cgImage: cg, scale: 1, orientation: .leftMirrored)
                    for q in [CGFloat(0.6), 0.4, 0.25] {
                        if let d = ui.jpegData(compressionQuality: q) {
                            if d.count <= 800_000 || q == 0.25 {
                                shot = "data:image/jpeg;base64," + d.base64EncodedString()
                                break
                            }
                        }
                    }
                }
            }

            let er = eyeRatios(f)
            if let el = er.left, let rr = er.right {
                if !earClosed {
                    earSamples.append((el + rr) / 2)
                    if earSamples.count > 30 { earSamples.removeFirst() }
                }
                let sorted = earSamples.sorted()
                let base = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
                if base > 0.10 {
                    if !earClosed, el < base * 0.70, rr < base * 0.70 {
                        earClosed = true
                    } else if earClosed, el > base * 0.88, rr > base * 0.88 {
                        earClosed = false
                        if now.timeIntervalSince(lastBlinkAt) > 0.8 {
                            lastBlinkAt = now
                            emit(.blink)
                        }
                    }
                }
            }

            if let mo = mouthOpen(f), mo > 0.30 {
                mouthFrames += 1
                if mouthFrames >= 2, now.timeIntervalSince(lastMouthAt) > 1.0 {
                    lastMouthAt = now
                    mouthFrames = 0
                    emit(.mouth)
                }
            } else {
                mouthFrames = 0
            }

            if let pg = poseProxy(f) {
                trackPose(yaw: pg.yaw, pitch: pg.pitch, size: Double(f.boundingBox.height), now: now)
            }
        } else if now.timeIntervalSince(lastFaceAt) > 0.5 {
            emit(.noFace)
        }

        if now.timeIntervalSince(lastTick) > 0.5 {
            lastTick = now
            emit(.tick)
        }
    }
}

struct FaceCameraPreview: UIViewRepresentable {
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = FaceLiveness.shared.captureSession
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) { }
}

enum FaceMatch {

    static func distance(shot dataURL: String, avatar: Data) async -> Double? {
        let head = dataURL.components(separatedBy: "base64,").last ?? ""
        guard !head.isEmpty, let shotData = Data(base64Encoded: head),
              let shot = UIImage(data: shotData), let av = UIImage(data: avatar) else { return nil }
        func print(_ img: UIImage) -> VNFeaturePrintObservation? {
            guard let cg = img.cgImage else { return nil }
            let req = VNGenerateImageFeaturePrintRequest()
            try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
            return req.results?.first
        }
        guard let a = print(shot), let b = print(av) else { return nil }
        var d: Float = 0
        guard (try? a.computeDistance(&d, to: b)) != nil else { return nil }
        return Double(d)
    }
}

extension FaceLiveness: AVCaptureDepthDataOutputDelegate {
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData,
                         timestamp: CMTime, connection: AVCaptureConnection) {
        guard running else { return }

        let conv = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let buf = conv.depthDataMap
        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buf) else { return }
        let w = CVPixelBufferGetWidth(buf), h = CVPixelBufferGetHeight(buf)
        let bpr = CVPixelBufferGetBytesPerRow(buf)
        guard w > 20, h > 20 else { return }
        var lo = Float.greatestFiniteMagnitude, hi: Float = 0
        var n = 0
        var y = h * 3 / 10
        while y < h * 7 / 10 {
            let row = base.advanced(by: y * bpr).assumingMemoryBound(to: Float.self)
            var x = w * 3 / 10
            while x < w * 7 / 10 {
                let v = row[x]
                if v.isFinite, v > 0 { lo = min(lo, v); hi = max(hi, v); n += 1 }
                x += 4
            }
            y += 4
        }
        guard n > 40, hi > lo else { return }
        depthRangeValue = Double(hi - lo)
    }
}
