import SwiftUI
import AVFoundation
import CoreImage
import Vision
import VisionKit

enum AlbumScan {

    static func small(_ image: UIImage, _ maxSide: CGFloat) -> UIImage {
        let long = max(image.size.width, image.size.height)
        guard long > maxSide, long > 0 else { return image }
        let k = maxSide / long
        let size = CGSize(width: image.size.width * k, height: image.size.height * k)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    static func decode(_ image: UIImage) -> String? {

        let work = small(image, 2000)
        guard let cg = work.cgImage else { return nil }
        let own = cgOrientation(work.imageOrientation)
        let orders: [CGImagePropertyOrientation] = [own, .up, .right, .down, .left]
        var tried = Set<String>()
        for o in orders {
            let key = "\(o.rawValue)"
            if tried.contains(key) { continue }
            tried.insert(key)
            if let hit = vision(cg, o) { return hit }
        }

        let det = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                             options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        if let ci = CIImage(image: work),
           let feats = det?.features(in: ci) as? [CIQRCodeFeature],
           let s = feats.compactMap({ $0.messageString }).first(where: { !$0.isEmpty }) {
            return s
        }
        return nil
    }

    private static func vision(_ cg: CGImage, _ o: CGImagePropertyOrientation) -> String? {
        let req = VNDetectBarcodesRequest()

        req.symbologies = [.qr, .code128, .code39, .code93, .ean13, .ean8, .upce, .itf14, .pdf417, .aztec, .dataMatrix]
        let handler = VNImageRequestHandler(cgImage: cg, orientation: o, options: [:])
        guard (try? handler.perform([req])) != nil else { return nil }
        return (req.results ?? []).compactMap({ $0.payloadStringValue }).first(where: { !$0.isEmpty })
    }

    static func ocrText(_ image: UIImage) -> String {
        guard let cg = image.cgImage else { return "" }
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        req.recognitionLanguages = ["zh-Hans", "en-US"]
        let handler = VNImageRequestHandler(cgImage: cg,
                                            orientation: cgOrientation(image.imageOrientation),
                                            options: [:])
        guard (try? handler.perform([req])) != nil else { return "" }
        return (req.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cgOrientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

@MainActor
func handleScanned(_ text: String, app: AppState) {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)

    if let invite = NearbyDropInvite.parse(t) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            app.nearbyDropInvite = invite
        }
        return
    }

    let isPayCode = (t.count == 18 && t.allSatisfy({ $0.isNumber }))
        || (t.contains("pay.html") && (t.contains("?c=") || t.contains("&c=") || t.contains("?u=") || t.contains("&u=")))
    if isPayCode {
        Task { @MainActor in
            do {
                let info = try await API.shared.payResolve(text: t)

                try? await Task.sleep(nanoseconds: 400_000_000)
                app.payScanText = t
                app.payScan = info
            } catch {
                app.show((error as? APIError)?.errorDescription ?? Tr("这不是收付款码"))
            }
        }
        return
    }

    if let r = t.range(of: "u="), t.contains("add.html") {
        var code = String(t[r.upperBound...])
        if let amp = code.firstIndex(of: "&") { code = String(code[..<amp]) }
        code = code.trimmingCharacters(in: .whitespaces)

        let myName = (app.me?.username ?? "").lowercased()
        if !code.isEmpty, !myName.isEmpty, code.lowercased().hasPrefix(myName + ".") {
            app.show(Tr("这是你自己的二维码，发给朋友扫才能加你"))
            return
        }
        if !code.isEmpty {
            openScannedCard(code, app: app)
            return
        }
        app.show(Tr("这个二维码里没有个人信息"))
        return
    }

    if !t.lowercased().hasPrefix("www."),
       !t.contains(" "), t.contains("."), t.count >= 6, t.count <= 40,
       t.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" }) {
        openScannedCard(t, app: app)
        return
    }

func openScannedCard(_ code: String, app: AppState) {
    Task { @MainActor in
        let res = await API.shared.userByCode(code)
        guard let u = res.user else {
            app.show(res.message.isEmpty ? Tr("这个二维码无效或者过期了") : res.message)
            return
        }

        try? await Task.sleep(nanoseconds: 400_000_000)
        app.scanCardUser = u
    }
}

    if let r = t.range(of: "c=") {
        var code = String(t[r.upperBound...])
        if let amp = code.firstIndex(of: "&") { code = String(code[..<amp]) }
        code = code.trimmingCharacters(in: .whitespaces)
        if !code.isEmpty {
            Task {
                let res = await API.shared.joinByInvite(code: code)
                if let err = res.error {
                    app.show(err)
                } else {
                    await app.loadChats()
                    app.show(Tr("已加入群聊"))

                    if let c = res.chat {
                        try? await Task.sleep(nanoseconds: 450_000_000)
                        app.openChatViaList(c)
                    }
                }
            }
            return
        }
        app.show(Tr("这个群二维码里没有邀请码"))
        return
    }

    var loginCode = t
    if !(loginCode.count == 6 && loginCode.allSatisfy({ $0.isNumber })),
       t.lowercased().contains("pair"), let r = t.range(of: "code=") {
        loginCode = String(t[r.upperBound...].prefix(6)).filter { $0.isNumber }
    }
    if loginCode.count == 6, loginCode.allSatisfy({ $0.isNumber }) {

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            app.pairApproveCode = loginCode
        }
        return
    }

    if let link = scannedWebLink(t) {
        presentAfterScanner {
            if let url = URL(string: link) {
                UIApplication.shared.open(url)
            } else {
                app.scanTextResult = t
            }
        }
        return
    }
    if t.count >= 3, t.count <= 24, !t.contains(" ") {
        Task {
            do {
                try await API.shared.addFriend(username: t)
                app.show("已向 \(t) 发送好友请求")
            } catch {
                app.show(Tr("扫到：") + t)
            }
        }
        return
    }
    presentAfterScanner {
        app.scanTextResult = t
    }
}

private func scannedWebLink(_ raw: String) -> String? {
    let text = raw.replacingOccurrences(of: "\\/", with: "/")
    let pattern = #"(?i)((?:https?://|www\.)[^\s"'<>]+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range),
          let hit = Range(match.range(at: 1), in: text) else { return nil }
    var link = String(text[hit])
    let trailing = CharacterSet(charactersIn: ")]}>,.;，。")
    while let last = link.last, last.unicodeScalars.allSatisfy(trailing.contains) {
        link.removeLast()
    }
    if link.lowercased().hasPrefix("www.") {
        link = "https://" + link
    }
    guard URL(string: link) != nil else { return nil }
    return link
}

private func presentAfterScanner(_ present: @escaping () -> Void) {
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 500_000_000)
        present()
    }
}

struct ScannedTextResultView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showBrowser = false

    let text: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    Text(text)
                        .font(pf(16))
                        .foregroundColor(C.label)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                }
                .background(C.cardBg)

                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = text
                    } label: {
                        Text(Tr("复制"))
                            .font(pf(15, .medium))
                            .foregroundColor(C.label)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(C.cardBg)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showBrowser = true
                    } label: {
                        Text(Tr("浏览器打开"))
                            .font(pf(15, .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(C.green)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(C.pageBg)
            }
            .background(C.pageBg)
            .navigationTitle(Tr("扫描结果"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(Tr("完成")) { dismiss() }
                }
            }
        }
        .fullScreenCover(isPresented: $showBrowser) {
            InAppBrowserView(initialURL: text)
        }
    }
}

struct ScannerView: View {
    var onFound: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var torch = false
    @State private var denied = false
    @State private var permissionChecked = false
    @State private var cameraStatus = CameraStatus.starting
    @State private var cameraRetryID = 0
    @State private var hint = "把二维码放进框里，自动识别"

    @State private var busy = false

    @State private var mode = 0
    @State private var ocrBusy = false
    @State private var showCamera = false
    @State private var resultText = ""
    @State private var resultTranslated = ""
    @State private var showResult = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !permissionChecked {
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text(Tr("正在打开相机…"))
                        .font(pf(14))
                        .foregroundColor(.white.opacity(0.78))
                }
            } else if denied {
                VStack(spacing: 12) {
                    Image(systemName: "camera.metering.unknown")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.8))
                    Text(Tr("没有相机权限"))
                        .font(pf(17, .medium))
                        .foregroundColor(.white)
                    Text(Tr("到「设置 → Luchat → 相机」里打开权限再回来"))
                        .font(pf(13))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            } else {
                liveScanner
                .ignoresSafeArea()

                ScanFrame()
                    .frame(width: 250, height: 250)

                if !useNativeScanner, cameraStatus != .running {
                    VStack(spacing: 10) {
                        if cameraStatus == .starting {
                            ProgressView().tint(.white)
                            Text(Tr("正在启动相机…"))
                                .font(pf(13))
                                .foregroundColor(.white.opacity(0.78))
                        } else {
                            Image(systemName: "camera.metering.unknown")
                                .font(.system(size: 26))
                                .foregroundColor(.white.opacity(0.82))
                            Text(Tr("相机没有启动"))
                                .font(pf(15, .medium))
                                .foregroundColor(.white)
                            Button {
                                cameraStatus = .starting
                                cameraRetryID += 1
                            } label: {
                                Text(Tr("重试"))
                                    .font(pf(14, .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 18)
                                    .frame(height: 36)
                                    .background(Capsule().fill(Color.black.opacity(0.42)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.28)))
                }

                VStack {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Color.black.opacity(0.35)))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Text(Tr("扫一扫"))
                            .font(pf(17, .semibold))
                            .foregroundColor(.white)
                        Spacer()
                        Button { torch.toggle() } label: {
                            Image(systemName: torch ? "bolt.fill" : "bolt.slash")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(torch ? Color.yellow : .white)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Color.black.opacity(0.35)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Spacer()

                    Text(hint)
                        .font(pf(13.5))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.35)))
                    Text(mode == 0
                         ? Tr("群二维码扫了直接进群；网页登录出的 6 位数码扫了就是确认登录")
                         : Tr("对着要翻译 / 取字的画面按「拍照」，也可以从相册挑一张"))
                        .font(pf(12))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 8)

                    HStack(spacing: 14) {
                        Button { AlbumPicker.present { image in pickPhoto(image) } } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 22))
                                Text(busy || ocrBusy ? Tr("识别中…") : Tr("相册"))
                                    .font(pf(13))
                            }
                            .foregroundColor(.white)
                            .frame(width: 74, height: 66)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.35)))
                        }
                        .buttonStyle(.plain)
                        .disabled(busy || ocrBusy)

                        if mode != 0 {
                            Button { showCamera = true } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "camera.fill").font(.system(size: 22))
                                    Text(Tr("拍照")).font(pf(13))
                                }
                                .foregroundColor(.white)
                                .frame(width: 74, height: 66)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.35)))
                            }
                            .buttonStyle(.plain)
                            .disabled(busy || ocrBusy)
                        }
                    }
                    .padding(.top, 16)

                    HStack(spacing: 36) {
                        ForEach(Array(["扫码", "翻译", "取字"].enumerated()), id: \.offset) { i, t in
                            Button {
                                withAnimation(.easeOut(duration: 0.15)) { mode = i }
                            } label: {
                                Text(Tr(t))
                                    .font(pf(15, mode == i ? .semibold : .regular))
                                    .foregroundColor(mode == i ? .white : .white.opacity(0.55))
                                    .padding(.bottom, 9)
                                    .overlay(alignment: .bottom) {
                                        if mode == i {
                                            Capsule().fill(Color(hex: 0x3ED37F))
                                                .frame(width: 18, height: 3)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 14)
                    .padding(.bottom, 30)
                }
            }
        }
        .statusBarHidden(false)
        .onAppear { askPermission() }
        .sheet(isPresented: $showCamera) {
            CameraPicker { img in pickPhoto(img) }
        }
        .sheet(isPresented: $showResult) { resultSheet }
    }

    private func scanAlbum(_ image: UIImage) {
        busy = true
        hint = Tr("正在识别…")
        Task.detached(priority: .userInitiated) {
            let text = AlbumScan.decode(image)
            await MainActor.run {
                busy = false
                if let t = text, !t.isEmpty {
                    hint = ""
                    onFound(t)
                    dismiss()
                } else {
                    hint = Tr("这张图里没找到二维码，换一张清楚点的试试")
                }
            }
        }
    }

    private func pickPhoto(_ image: UIImage) {
        if mode == 0 { scanAlbum(image); return }
        ocrBusy = true
        hint = Tr("正在识别文字…")
        Task.detached(priority: .userInitiated) {
            let text = AlbumScan.ocrText(image)
            await MainActor.run {
                ocrBusy = false
                hint = mode == 0 ? "把二维码放进框里，自动识别" : "对着要翻译 / 取字的画面按「拍照」"
                guard !text.isEmpty else {
                    hint = Tr("这张图里没认出文字，换一张清楚点的")
                    return
                }
                resultText = text
                resultTranslated = ""
                showResult = true
                if mode == 1 { Task { await translate() } }
            }
        }
    }

    private func translate() async {
        ocrBusy = true
        let out = await API.shared.scanTranslate(resultText, to: "中文")
        ocrBusy = false
        resultTranslated = out ?? Tr("翻译失败：检查后台有没有配 AI 密钥")
    }

    private var resultSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if mode == 1 {
                        resultCard(Tr("译文"), resultTranslated.isEmpty ? Tr("正在翻译…") : resultTranslated, hot: true)
                        resultCard(Tr("原文"), resultText, hot: false)
                    } else {
                        resultCard(Tr("识别到的文字"), resultText, hot: false)
                    }
                }
                .padding(14)
            }
            .background(C.pageBg)
            .navigationTitle(mode == 1 ? Tr("翻译") : Tr("取字"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(Tr("关闭")) { showResult = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(Tr("复制")) {
                        let t = (mode == 1 && !resultTranslated.isEmpty) ? resultTranslated : resultText
                        UIPasteboard.general.string = t
                    }
                }
            }
        }
    }

    private func resultCard(_ title: String, _ text: String, hot: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(pf(12.5)).foregroundColor(C.subLabel)
            Text(text.isEmpty ? "—" : text)
                .font(pf(16))
                .foregroundColor(C.label)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background { CardGlassBox(radius: 14) }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(hot ? C.green.opacity(0.45) : C.hairline, lineWidth: hot ? 1.2 : 0.6))
    }

    private func askPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            denied = false
            permissionChecked = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async {
                    denied = !ok
                    permissionChecked = true
                }
            }
        default:
            denied = true
            permissionChecked = true
        }
    }

    private var useNativeScanner: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    @ViewBuilder
    private var liveScanner: some View {
        if useNativeScanner {
            NativeQRScanner(torch: $torch, acceptsCodes: mode == 0) { text in
                onFound(text)
                dismiss()
            }
        } else {
            CameraPreview(torch: $torch, status: $cameraStatus, retryID: cameraRetryID) { text in
                onFound(text)
                dismiss()
            }
        }
    }
}

private struct ScanFrame: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, len: CGFloat = 34, lw: CGFloat = 3
            ZStack {
                RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.28), lineWidth: 1)
                corner(w: len, lw: lw).position(x: len / 2, y: len / 2)
                corner(w: len, lw: lw).rotationEffect(.degrees(90)).position(x: w - len / 2, y: len / 2)
                corner(w: len, lw: lw).rotationEffect(.degrees(180)).position(x: w - len / 2, y: h - len / 2)
                corner(w: len, lw: lw).rotationEffect(.degrees(270)).position(x: len / 2, y: h - len / 2)
            }
        }
    }

    private func corner(w: CGFloat, lw: CGFloat) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: w))
            p.addLine(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: w, y: 0))
        }
        .stroke(Color.white, style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
        .frame(width: w, height: w)
    }
}

private enum CameraStatus: Equatable {
    case starting
    case running
    case failed
}

private struct NativeQRScanner: UIViewControllerRepresentable {
    @Binding var torch: Bool
    var acceptsCodes: Bool
    var onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [.qr, .ean13, .ean8, .upce,
                                       .code128, .code39, .code93, .itf14,
                                       .pdf417, .aztec, .dataMatrix])
            ],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        context.coordinator.scanner = scanner
        context.coordinator.acceptsCodes = acceptsCodes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if DataScannerViewController.isAvailable, !scanner.isScanning {
                try? scanner.startScanning()
            }
        }
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.acceptsCodes = acceptsCodes
        context.coordinator.setTorch(torch)
        if DataScannerViewController.isAvailable, !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController,
                                          coordinator: Coordinator) {
        if scanner.isScanning { scanner.stopScanning() }
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        weak var scanner: DataScannerViewController?
        var acceptsCodes = true
        private var done = false
        private let onCode: (String) -> Void

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            accept(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didTapOn item: RecognizedItem) {
            accept([item])
        }

        private func accept(_ items: [RecognizedItem]) {
            guard acceptsCodes, !done else { return }
            for item in items {
                guard case .barcode(let barcode) = item,
                      let text = barcode.payloadStringValue, !text.isEmpty else { continue }
                done = true
                scanner?.stopScanning()
                onCode(text)
                return
            }
        }

        func setTorch(_ on: Bool) {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                       for: .video,
                                                       position: .back),
                  device.hasTorch,
                  (try? device.lockForConfiguration()) != nil else { return }
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    @Binding var torch: Bool
    @Binding var status: CameraStatus
    var retryID: Int
    var onCode: (String) -> Void

    func makeCoordinator() -> Coordinator {
        let statusBinding = _status
        return Coordinator(onCode: onCode) { next in
            guard statusBinding.wrappedValue != next else { return }
            statusBinding.wrappedValue = next
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        context.coordinator.start(in: view, torch: torch, retryID: retryID)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.setTorch(torch)
        context.coordinator.update(retryID: retryID)
    }

    static func dismantleUIView(_ uiView: PreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class PreviewView: UIView {
        let videoLayer = AVCaptureVideoPreviewLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            layer.addSublayer(videoLayer)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            backgroundColor = .black
            layer.addSublayer(videoLayer)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            videoLayer.frame = bounds
            CATransaction.commit()
        }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "chris.scanner")
        private var device: AVCaptureDevice?
        private weak var previewView: PreviewView?
        private var observers: [NSObjectProtocol] = []
        private var configured = false
        private var active = false
        private var lastRetryID = 0
        private var done = false
        private let onCode: (String) -> Void
        private let onStatus: (CameraStatus) -> Void

        init(onCode: @escaping (String) -> Void,
             onStatus: @escaping (CameraStatus) -> Void) {
            self.onCode = onCode
            self.onStatus = onStatus
        }

        func start(in view: PreviewView, torch: Bool, retryID: Int) {
            guard !active else { return }
            active = true
            previewView = view
            lastRetryID = retryID
            installObservers()
            guard configure() else {
                active = false
                removeObservers()
                publish(.failed)
                return
            }
            attachPreview(to: view)
            setTorch(torch)
            startRunning(attempt: 0)
        }

        private func configure() -> Bool {
            if configured { return !session.inputs.isEmpty && !session.outputs.isEmpty }
            guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video,
                                                    position: .back),
                  let input = try? AVCaptureDeviceInput(device: dev) else {
                return false
            }
            device = dev
            session.beginConfiguration()
            session.sessionPreset = .high
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                return false
            }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                session.removeInput(input)
                session.commitConfiguration()
                return false
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr, .ean13, .ean8, .upce, .code128, .code39, .code93,
                                          .itf14, .pdf417, .aztec, .dataMatrix]
            session.commitConfiguration()
            configured = true
            return true
        }

        private func attachPreview(to view: PreviewView) {
            view.videoLayer.session = session
            view.videoLayer.videoGravity = .resizeAspectFill
            view.layoutIfNeeded()
            if let connection = view.videoLayer.connection {
                connection.isEnabled = true
                if #available(iOS 17.0, *) {
                    if connection.isVideoRotationAngleSupported(90) {
                        connection.videoRotationAngle = 90
                    }
                } else {
                    connection.videoOrientation = .portrait
                }
            }
        }

        private func startRunning(attempt: Int) {
            queue.asyncAfter(deadline: .now() + (attempt == 0 ? 0.12 : 0)) { [weak self] in
                guard let self, self.active else { return }
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                let running = self.session.isRunning
                if running {
                    DispatchQueue.main.async { [weak self] in
                        if let view = self?.previewView { self?.attachPreview(to: view) }
                    }
                }
                self.publish(running ? .running : (attempt >= 3 ? .failed : .starting))
                if !running, attempt < 3, self.active {
                    self.queue.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                        self?.startRunning(attempt: attempt + 1)
                    }
                }
            }
        }

        private func restart() {
            queue.async { [weak self] in
                guard let self, self.active else { return }
                if self.session.isRunning { self.session.stopRunning() }
                self.startRunning(attempt: 0)
            }
        }

        private func installObservers() {
            guard observers.isEmpty else { return }
            let center = NotificationCenter.default
            observers.append(center.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification,
                object: session,
                queue: .main
            ) { [weak self] _ in
                self?.restart()
            })
            observers.append(center.addObserver(
                forName: AVCaptureSession.interruptionEndedNotification,
                object: session,
                queue: .main
            ) { [weak self] _ in
                self?.restart()
            })
            observers.append(center.addObserver(
                forName: AVCaptureSession.wasInterruptedNotification,
                object: session,
                queue: .main
            ) { [weak self] _ in
                self?.publish(.starting)
            })
            observers.append(center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.restart()
            })
        }

        private func removeObservers() {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()
        }

        private func publish(_ next: CameraStatus) {
            DispatchQueue.main.async { [onStatus] in
                onStatus(next)
            }
        }

        func update(retryID: Int) {
            guard retryID != lastRetryID else { return }
            lastRetryID = retryID
            if configured {
                restart()
            } else if let view = previewView {
                start(in: view, torch: device?.torchMode == .on, retryID: retryID)
            }
        }

        func stop() {
            active = false
            removeObservers()
            queue.async { [session] in if session.isRunning { session.stopRunning() } }
        }

        func setTorch(_ on: Bool) {
            guard let dev = device, dev.hasTorch else { return }
            try? dev.lockForConfiguration()
            dev.torchMode = on ? .on : .off
            dev.unlockForConfiguration()
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput objects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !done else { return }
            for obj in objects {
                guard let code = obj as? AVMetadataMachineReadableCodeObject,
                      let text = code.stringValue, !text.isEmpty else { continue }
                done = true
                stop()
                onCode(text)
                return
            }
        }

        deinit {
            removeObservers()
        }
    }
}
