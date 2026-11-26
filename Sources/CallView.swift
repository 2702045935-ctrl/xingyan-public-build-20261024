import SwiftUI
import WebRTC

struct CallOverlay: View {
    @ObservedObject private var call = CallCenter.shared

    var body: some View {
        if call.phase != .idle {
            if call.minimized {

                CallMiniWindow()
                    .zIndex(999)
            } else {
                CallView()
                    .zIndex(999)
            }
        }
    }
}

struct CallDialogOverlay: View {
    @ObservedObject private var call = CallCenter.shared

    var body: some View {
        ZStack {
            if let d = call.dialog {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { call.dismissDialog() }

                VStack(spacing: 0) {
                    VStack(spacing: 6) {
                        Text(d.title)
                            .font(pf(16, .medium))
                            .foregroundColor(C.chatTimeInk)
                            .multilineTextAlignment(.center)
                        if !d.detail.isEmpty {
                            Text(d.detail)
                                .font(pf(13))
                                .foregroundColor(C.chatTimeInk.opacity(0.75))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 18)

                    Rectangle()
                        .fill(C.chatTimeInk.opacity(0.18))
                        .frame(height: 0.5)

                    Button {
                        call.dismissDialog()
                    } label: {
                        Text(d.okText)
                            .font(pf(16, .medium))
                            .foregroundColor(C.chatTimeInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 268)
                .background(
                    RoundedRectangle(cornerRadius: max(12, L.o("chatTimeRadius", 4) + 8), style: .continuous)
                        .fill(C.chatTimeBg)
                )
                .transition(.scale(scale: 0.94).combined(with: .opacity))
                .zIndex(1000)
            }
        }
        .zIndex(1000)
        .animation(.easeOut(duration: 0.16), value: call.dialog)
    }
}

struct CallView: View {
    @ObservedObject private var call = CallCenter.shared

    @EnvironmentObject var app: AppState

    private struct CallMsgBanner: Equatable {
        var chatId: String
        var name: String
        var text: String
    }
    @State private var msgBanner: CallMsgBanner? = nil
    @State private var bannerTask: Task<Void, Never>? = nil

    @State private var lastMsgSeen: [String: String] = [:]
    @State private var showInvite = false

    @State private var pipX: CGFloat? = nil
    @State private var pipY: CGFloat? = nil
    @State private var pipDrag: CGSize = .zero

    @State private var showReplies = false

    @State private var audioDevices: [CallAudioRoute] = []
    @State private var showAudioDevices = false
    @State private var showMicAlert = false

    private var blurRadius: CGFloat { UIConfig.num("callBackdropBlur", 60) }
    private var tint: CGFloat { UIConfig.num("callGlassTint", 0.45) }

    private var bgPath: String {
        let v = effectiveGlobalChatBackground(app.me?.chatBackground)
        if v.isEmpty || v == "auto" {
            let def = app.defaultChatBackground
            return effectiveDefaultChatBackground(def)
        }
        return v
    }

    var body: some View {
        ZStack {
            backdrop

            if call.isGroupCall {
                groupLayer
            } else if call.isVideo && call.phase == .active {
                videoLayer
            } else {
                avatarLayer
            }

            VStack(spacing: 0) {
                topBar
                if let b = msgBanner { msgBannerView(b) }
                Spacer(minLength: 0)

                if micUnavailable { micBanner }
                bottomBar
            }
        }
        .sheet(isPresented: $showInvite) {
            inviteSheet
        }

        .confirmationDialog(Tr("拒绝并回复"), isPresented: $showReplies, titleVisibility: .visible) {
            Button(Tr("在忙，稍后联系你")) { call.reject(withReply: "在忙，稍后联系你") }
            Button(Tr("不方便接听，稍后回你")) { call.reject(withReply: "不方便接听，稍后回你") }
            Button(Tr("在开车，晚点回你")) { call.reject(withReply: "在开车，晚点回你") }
            Button(Tr("取消"), role: .cancel) { }
        }

        .confirmationDialog(Tr("声音输出") + "（" + call.currentAudioDeviceName + "）",
                            isPresented: $showAudioDevices, titleVisibility: .visible) {
            ForEach(audioDevices) { d in
                Button((d.name == call.currentAudioDeviceName ? "✓ " : "") + d.name) {
                    call.selectAudioDevice(d)
                }
            }
            Button(Tr("取消"), role: .cancel) { }
        }
        .alert(Tr("麦克风没有开启"), isPresented: $showMicAlert) {
            Button(Tr("去设置")) { call.openMicSettings() }
            Button(Tr("继续通话"), role: .cancel) { }
        } message: {
            Text(Tr("对方现在听不到你的声音。请在系统设置里允许麦克风，或检查是否被其他通话占用。"))
        }
        .onChange(of: micUnavailable) { blocked in
            if blocked, call.phase != .idle { showMicAlert = true }
        }

        .task(id: call.callId) {

            VideoBlur.shared.onAutoOff = { msg in app.show(msg) }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { break }
                scanNewMessages()
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {

            DispatchQueue.main.async {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
                if micUnavailable, call.phase != .idle { showMicAlert = true }
            }
        }
    }

    private var micUnavailable: Bool {
        guard !call.muted else { return false }
        return call.micBlocked
    }

    private func scanNewMessages() {
        switch call.phase {
        case .idle: return
        default: break
        }
        let mine = app.me?.id ?? ""
        for c in app.chats {
            guard let lm = c.lastMessage, let mid = lm.id, !mid.isEmpty else { continue }
            let sender = lm.senderId ?? ""
            if sender == mine || sender.isEmpty { lastMsgSeen[c.id] = mid; continue }
            let old = lastMsgSeen[c.id]
            lastMsgSeen[c.id] = mid
            guard let old = old, old != mid else { continue }
            if c.muted == true { continue }
            let t = (lm.preview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            showBanner(chatId: c.id, name: c.title ?? Tr("新消息"),
                       text: t.isEmpty ? Tr("[新消息]") : t)
            return
        }
    }

    private func showBanner(chatId: String, name: String, text: String) {
        withAnimation(.easeOut(duration: 0.18)) {
            msgBanner = CallMsgBanner(chatId: chatId, name: name, text: String(text.prefix(30)))
        }
        bannerTask?.cancel()
        bannerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { withAnimation(.easeOut(duration: 0.18)) { msgBanner = nil } }
        }
    }

    private func msgBannerView(_ b: CallMsgBanner) -> some View {
        Button {
            msgBanner = nil
            call.minimize()
            if let c = app.chats.first(where: { $0.id == b.chatId }) { app.openChatViaList(c) }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "message.fill").font(.system(size: 12, weight: .semibold))
                Text(b.name).font(pf(13, .medium)).lineLimit(1)
                Text(b.text).font(pf(13)).lineLimit(1).foregroundColor(.white.opacity(0.82))
                Spacer(minLength: 0)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.black.opacity(0.28)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.22),
                                               lineWidth: 0.7))
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var backdrop: some View {
        ZStack {
            Color(red: 0.10, green: 0.11, blue: 0.10)

            if !call.peerAvatar.isEmpty {
                RemoteImage(path: call.peerAvatar)
                    .blur(radius: blurRadius)
                    .scaleEffect(1.35)
            } else if !bgPath.isEmpty {
                RemoteImage(path: bgPath)
                    .blur(radius: blurRadius)
                    .scaleEffect(1.25)
            }
            Color.black.opacity(tint)
        }
        .ignoresSafeArea()
    }

    private var avatarLayer: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: max(58, 176 - L.safeTop))

            Avatar(path: call.peerAvatar, size: 112, radius: 56, circle: true)
                .overlay {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.44),
                                    Color.white.opacity(0.08),
                                    Color.black.opacity(0.20)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.9
                        )
                }
                .shadow(color: .black.opacity(0.34), radius: 24, y: 10)

            Text(call.peerName)
                .font(pfExact(29, .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .padding(.top, 20)

            Text(statusText)
                .font(pfExact(15.5, .medium))
                .foregroundColor(.white.opacity(0.66))
                .padding(.top, 7)

            if let err = call.errorText, !err.isEmpty, call.phase == .outgoing {
                Text(err)
                    .font(pfExact(14, .medium))
                    .foregroundColor(Color(hex: 0xFFB4AB))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 10)
            }

            if !hintText.isEmpty {
                Text(hintText)
                    .font(pfExact(14))
                    .foregroundColor(.white.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 28)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var videoLayer: some View {
        ZStack {

            VideoSurface(track: call.remoteVideo)
                .ignoresSafeArea()
            if call.remoteVideo == nil {
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text(Tr("正在连接画面…"))
                        .font(pfExact(14))
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(call.peerName)
                            .font(pfExact(17, .medium))
                            .foregroundColor(.white)
                        Text(statusText)
                            .font(pfExact(13))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                Spacer()

                GeometryReader { geo in
                    let w: CGFloat = 104
                    let h: CGFloat = 148
                    let maxX = max(8, geo.size.width - w - 12)
                    let minY: CGFloat = 74
                    let maxY = max(minY, geo.size.height - h - 150)
                    let homeX = geo.size.width - w - 16
                    let homeY = geo.size.height - h - 150
                    let x = min(max((pipX ?? homeX) + pipDrag.width, 8), maxX)
                    let y = min(max((pipY ?? homeY) + pipDrag.height, minY), maxY)
                    pipBody(w: w, h: h)
                        .position(x: x + w / 2, y: y + h / 2)
                        .gesture(
                            DragGesture(minimumDistance: 5)
                                .onChanged { v in pipDrag = v.translation }
                                .onEnded { v in
                                    let nx = (pipX ?? homeX) + v.translation.width
                                    let ny = (pipY ?? homeY) + v.translation.height

                                    pipX = nx + w / 2 < geo.size.width / 2 ? 8 : maxX
                                    pipY = min(max(ny, minY), maxY)
                                    pipDrag = .zero
                                }
                        )
                }
            }

            VStack {
                HStack {
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        topPill(symbol: "arrow.triangle.2.circlepath.camera",
                                on: false,
                                hint: "翻转") { call.flipCamera() }
                        topPill(symbol: call.cameraOff ? "video.slash.fill" : "video.fill",
                                on: call.cameraOff,
                                hint: call.cameraOff ? "摄像头已关" : "摄像头已开") { call.toggleCamera() }
                    }
                    .padding(.trailing, 14)
                }
                .padding(.top, L.navH + 52)
                Spacer(minLength: 0)
            }
        }
    }

    private func pipBody(w: CGFloat, h: CGFloat) -> some View {
        VideoSurface(track: call.localVideo)
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color.white.opacity(0.22), lineWidth: 1))

        .overlay {
            if call.cameraOff {
                ZStack {
                    Color.black.opacity(0.72)
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { call.flipCamera() }
    }

    private func topPill(symbol: String, on: Bool, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(on ? .black : .white)
                .frame(width: 44, height: 44)
                .background {
                    ZStack {
                        Circle().fill(.ultraThinMaterial)
                        Circle().fill(on ? Color.white : Color.black.opacity(0.24))
                        Circle().stroke(Color.white.opacity(0.34), lineWidth: 0.7)
                    }
                }
                .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(hint))
    }

    private var groupLayer: some View {
        VStack(spacing: 14) {
            Text(call.groupTitle.isEmpty ? Tr("群语音通话") : call.groupTitle)
                .font(pf(17, .semibold))
                .foregroundColor(.white.opacity(0.92))
                .lineLimit(1)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3),
                      spacing: 16) {
                ForEach(call.roster) { m in
                    VStack(spacing: 6) {
                        ZStack {
                            Avatar(path: m.avatar, size: 64, radius: 32, circle: true)

                            if speakOn(m) {
                                Circle()
                                    .stroke(C.green.opacity(0.92), lineWidth: 2)
                                    .frame(width: 72, height: 72)
                                    .shadow(color: C.green.opacity(0.48), radius: 8)
                            }
                            if m.muted {
                                Image(systemName: "mic.slash.fill")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(4)
                                    .background(Circle().fill(Color.black.opacity(0.55)))
                                    .offset(x: 23, y: 23)
                            }
                        }
                        Text(m.name.isEmpty ? Tr("成员") : m.name)
                            .font(pf(12.5))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 34)
            Text("\(call.roster.count) " + Tr("人在通话中"))
                .font(pf(12.5))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private func speakOn(_ m: GroupCallMember) -> Bool {
        let lv = call.speakerLevels[m.userId] ?? 0
        guard lv > 0.10 else { return false }
        let top = call.speakerLevels.values.max() ?? 0
        return lv >= top
    }

    private var statusText: String {
        if call.isGroupCall {
            switch call.phase {
            case .incoming:   return Tr("群组来电")
            case .outgoing:   return Tr("正在呼叫…")
            case .connecting: return Tr("正在接通…")
            case .active:     return timeText
            case .idle:       return ""
            }
        }
        switch call.phase {
        case .incoming:   return call.isVideo ? Tr("视频来电") : Tr("语音来电")
        case .outgoing:   return Tr("正在呼叫…")
        case .connecting: return Tr("正在接通…")
        case .active:     return timeText
        case .idle:       return ""
        }
    }

    private var hintText: String {
        let t = call.tip
        if call.phase == .idle { return "" }
        if t == "未接听" || t == "对方已拒绝" || t == "对方不在线" { return t + "，建议稍后尝试" }
        if t.contains("失败") || t.contains("断开") { return t }

        if call.weakNet { return "网络不太稳定，正在重连…" }

        if call.peerCameraOff { return "对方已关闭摄像头" }
        if call.peerMuted { return "对方已静音" }
        return ""
    }

    private var timeText: String {
        String(format: "%02d:%02d", call.seconds / 60, call.seconds % 60)
    }

    private var bottomBar: some View {
        Group {
            if call.phase == .incoming {
                VStack(spacing: 17) {
                    HStack(spacing: 76) {
                        systemCallAction(symbol: "phone.down.fill",
                                         label: Tr("拒绝"),
                                         tint: Color(hex: 0xFF453A)) {
                            call.reject()
                        }
                        systemCallAction(symbol: "phone.fill",
                                         label: Tr("接听"),
                                         tint: Color(hex: 0x30D158)) {
                            if call.isGroupCall { call.acceptGroupCall() } else { call.accept() }
                        }
                    }

                    Button { showReplies = true } label: {
                        Text(Tr("拒绝并回复"))
                            .font(pf(13.5, .medium))
                            .foregroundColor(.white.opacity(0.88))
                            .padding(.horizontal, 17)
                            .frame(height: 34)
                            .background {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Capsule().fill(Color.black.opacity(0.12)))
                                    .overlay(Capsule().stroke(Color.white.opacity(0.28),
                                                               lineWidth: 0.7))
                            }
                    }
                    .buttonStyle(.plain)

                    if call.isVideo && !call.isGroupCall {
                        Button { call.accept(asAudio: true) } label: {
                            Text(Tr("语音接听"))
                                .font(pf(13.5, .medium))
                                .foregroundColor(.white.opacity(0.88))
                                .padding(.horizontal, 17)
                                .frame(height: 34)
                                .background {
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .overlay(Capsule().fill(Color.black.opacity(0.12)))
                                        .overlay(Capsule().stroke(Color.white.opacity(0.28),
                                                                   lineWidth: 0.7))
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 46)
            } else if call.isVideo {
                VStack(spacing: 18) {
                    HStack(spacing: 32) {
                        if call.phase == .active {
                            micKey
                            speakerKey
                            if !call.isGroupCall {
                                cameraKey
                            }
                        } else {
                            micKey
                            flipKey
                            cameraKey
                        }
                    }

                    hangupKey

                    if call.phase == .active && !call.isGroupCall {
                        Button { call.switchVideo() } label: { switchLabel }
                            .buttonStyle(.plain)
                    }

                    if call.phase == .active {
                        Button { call.toggleBlurBackground() } label: {
                            Text(call.blurBackground ? Tr("关闭背景模糊") : Tr("模糊背景"))
                                .font(pf(14))
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.horizontal, 16)
                                .frame(height: 32)
                                .background {
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .overlay(Capsule().fill(Color.white.opacity(
                                            call.blurBackground ? 0.22 : 0.05
                                        )))
                                        .overlay(Capsule().stroke(Color.white.opacity(0.28),
                                                                   lineWidth: 0.7))
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 38)
            } else {
                VStack(spacing: 18) {
                    HStack(spacing: 42) {
                        micKey
                        if call.phase == .active {
                            speakerKey
                        }
                    }

                    hangupKey

                    if call.phase == .active && !call.isGroupCall {
                        Button { call.switchVideo() } label: { switchLabel }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 46)
            }
        }
    }

    private var switchLabel: some View {
        Text(call.isVideo ? Tr("切换为语音通话") : Tr("切换为视频通话"))
            .font(pf(13.5, .medium))
            .foregroundColor(.white.opacity(0.88))
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.black.opacity(0.12)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.26),
                                               lineWidth: 0.7))
            }
    }

    private var micKey: some View {
        systemControl(
            symbol: call.muted ? "mic.slash.fill" : "mic.fill",
            label: call.muted ? Tr("麦克风已关") : Tr("麦克风"),
            engaged: call.muted
        ) {
            call.toggleMute()
        }
    }

    private var micBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            Text(Tr("麦克风没开，对方听不到你"))
                .font(pfExact(13.5))
                .foregroundColor(.white)
                .lineLimit(2)
            Spacer(minLength: 6)
            Button { call.retryMic() } label: {
                Text(Tr("重试"))
                    .font(pfExact(13.5, .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .overlay(Capsule().stroke(Color.white.opacity(0.75), lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button { call.openMicSettings() } label: {
                Text(Tr("去开启"))
                    .font(pfExact(13.5, .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(hex: 0xE08A10).opacity(0.24))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 0.7)
                }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var speakerKey: some View {
        systemControl(
            symbol: call.speakerOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
            label: Tr("扬声器"),
            engaged: call.speakerOn
        ) {
            call.toggleSpeaker()
        }

            .onLongPressGesture(minimumDuration: 0.35) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                audioDevices = call.audioDevices()
                showAudioDevices = true
            }
    }

    private var hangupKey: some View {
        systemCallAction(
            symbol: "phone.down.fill",
            label: call.phase == .active ? Tr("挂断") : Tr("取消"),
            tint: Color(hex: 0xFF453A)
        ) {
            call.hangup()
        }
    }

    private var flipKey: some View {
        systemControl(
            symbol: "arrow.triangle.2.circlepath.camera",
            label: Tr("翻转")
        ) {
            call.flipCamera()
        }
    }

    private var cameraKey: some View {
        systemControl(
            symbol: call.cameraOff ? "video.slash.fill" : "video.fill",
            label: Tr("摄像头"),
            engaged: call.cameraOff
        ) {
            call.toggleCamera()
        }
    }

    private func systemControl(symbol: String, label: String,
                               engaged: Bool = false,
                               action: @escaping () -> Void) -> some View {
        VStack(spacing: 9) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(engaged ? .black : .white)
                    .frame(width: 64, height: 64)
                    .background {
                        ZStack {
                            Circle().fill(.ultraThinMaterial)
                            Circle().fill(engaged
                                          ? Color.white
                                          : Color.black.opacity(0.22))
                            Circle().stroke(Color.white.opacity(0.34),
                                            lineWidth: 0.7)
                        }
                    }
                    .shadow(color: .black.opacity(0.18), radius: 9, y: 4)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)

            Text(label)
                .font(pfExact(12.5, .medium))
                .foregroundColor(.white.opacity(0.76))
                .lineLimit(1)
        }
    }

    private func systemCallAction(symbol: String, label: String,
                                  tint: Color,
                                  action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 72, height: 72)
                    .background {
                        Circle().fill(
                            LinearGradient(
                                colors: [tint.opacity(0.96), tint.opacity(0.80)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(Circle().fill(Color.white.opacity(0.08)))
                        .overlay(Circle().stroke(Color.white.opacity(0.24),
                                                 lineWidth: 0.8))
                    }
                    .shadow(color: tint.opacity(0.32), radius: 13, y: 6)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)

            Text(label)
                .font(pfExact(12.5, .medium))
                .foregroundColor(.white.opacity(0.78))
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                call.minimize()
            } label: {
                Image(systemName: "rectangle.inset.bottomright.filled")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background { callTopGlass }
            }
            .buttonStyle(.plain)
            .padding(.leading, 14)
            .accessibilityLabel(Tr("最小化通话"))

            Spacer()

            Button {
                showInvite = true
            } label: {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background { callTopGlass }
            }
            .buttonStyle(.plain)
            .padding(.trailing, 14)
            .accessibilityLabel(Tr("邀请好友加入通话"))
        }
        .padding(.top, 16)
    }

    private var callTopGlass: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().fill(Color.black.opacity(0.22))
            Circle().stroke(Color.white.opacity(0.32), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
    }

    private var miniBarOld: some View {
        HStack(spacing: 8) {
            Circle().fill(C.green).frame(width: 8, height: 8)
            Text(call.phase == .active ? "通话中 \(timeText)" : call.tip)
                .font(pfExact(14))
                .foregroundColor(.white)
            Spacer(minLength: 0)
            Button {
                call.restore()
            } label: {
                Text(Tr("回到通话")).font(pfExact(14)).foregroundColor(Color(hex: 0x19A47A))
            }
            .buttonStyle(.plain)
            Button {
                call.hangup()
            } label: {
                CallIcon(key: "ui.callHangup", symbol: "phone.down.fill", builtin: I.callHangup, size: 24)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(Capsule().fill(Color.black.opacity(0.72)))
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @State private var groupMembers: [User] = []

    private var inviteList: [User] {
        if call.isGroupCall && !call.groupChatId.isEmpty {
            let mine = app.me?.id ?? ""
            return groupMembers.filter { u in
                u.id != mine && !call.roster.contains(where: { $0.userId == u.id })
            }
        }
        return app.contacts
    }

    private var inviteSheet: some View {
        NavigationStack {
            List {
                Section {
                    if inviteList.isEmpty {
                        Text(call.isGroupCall
                             ? Tr("这个群里没有可以再拉的人了（要么已经在通话里，要么只有你自己）。想拉别人先把人加进群。")
                             : Tr("还没有好友可以邀请"))
                            .font(pf(13.5)).foregroundColor(C.subLabel)
                    }
                    ForEach(inviteList) { u in
                        Button {
                            showInvite = false
                            let name = u.nickname ?? u.username ?? "好友"
                            Task {

                                if call.isGroupCall {
                                    call.inviteToCall(u.id)
                                    app.show(Tr("已邀请 ") + name + Tr(" 加入通话"))
                                } else {
                                    let msg = await call.invite(userId: u.id, name: name)
                                    app.show(msg)
                                }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Avatar(path: u.avatar ?? "", size: 36, radius: 6)
                                Text(u.nickname ?? u.username ?? "好友").foregroundColor(C.label)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(call.groupCallFull
                         ? Tr("通话人数已满（最多 9 人）")
                         : Tr("邀请好友加入通话") + "（" + String(call.roster.count) + "/9）")
                } footer: {
                    Text(call.isGroupCall
                         ? Tr("群通话只能邀请**本群成员**（对方会看到群通话来电，接听即入会）。不是群成员的，先拉进群再来邀请。")
                         : Tr("对方会收到一条邀请消息，点那条消息就能回拨给你。"))
                }
            }
            .navigationTitle(Tr("添加通话"))
            .navigationBarTitleDisplayMode(.inline)
        }

        .task {
            guard call.isGroupCall, !call.groupChatId.isEmpty, groupMembers.isEmpty else { return }
            if let r = try? await API.shared.chatMembers(chatId: call.groupChatId) {
                groupMembers = r.members
            }
        }
    }
}

struct CallMiniWindow: View {
    @ObservedObject private var call = CallCenter.shared

    @State private var miniX: CGFloat? = nil
    @State private var miniY: CGFloat? = nil
    @State private var dragging: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let w: CGFloat = call.isVideo ? 108 : 146
            let h: CGFloat = call.isVideo ? 144 : 48

            let topSafe = max(geo.safeAreaInsets.top, 24)
            let minY = topSafe - 6
            let maxX = max(8, geo.size.width - w - 8)
            let maxY = max(minY, geo.size.height - h - 90)
            let homeX = geo.size.width - w - 10
            let homeY = topSafe + 4
            let x = min(max((miniX ?? homeX) + dragging.width, 8), maxX)
            let y = min(max((miniY ?? homeY) + dragging.height, minY), maxY)
            windowBody(w: w, h: h)
                .position(x: x + w / 2, y: y + h / 2)
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { v in dragging = v.translation }
                        .onEnded { v in
                            let nx = (miniX ?? homeX) + v.translation.width
                            let ny = (miniY ?? homeY) + v.translation.height

                            miniX = nx + w / 2 < geo.size.width / 2 ? 8 : maxX
                            miniY = min(max(ny, minY), maxY)
                            dragging = .zero
                        }
                )
        }
    }

    private func windowBody(w: CGFloat, h: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if call.isVideo {
                    ZStack {
                        VideoSurface(track: call.remoteVideo)
                        if call.remoteVideo == nil {
                            Avatar(path: call.peerAvatar, size: 44, radius: 8)
                        }
                    }
                } else {
                    HStack(spacing: 9) {
                        Avatar(path: call.peerAvatar, size: 28, radius: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(call.peerName)
                                .font(pfExact(13, .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(call.phase == .active ? miniTimeText : (call.tip.isEmpty ? "通话中" : call.tip))
                                .font(pfExact(11))
                                .foregroundColor(.white.opacity(0.72))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .background(Color(hex: 0x19A47A))
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.18), lineWidth: 0.5))
            .contentShape(Rectangle())
            .onTapGesture { call.restore() }

            Button {
                call.hangup()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.black.opacity(0.55)))
            }
            .buttonStyle(.plain)
            .padding(5)
        }
        .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
    }

    private var miniTimeText: String {
        let s = call.seconds
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%02d:%02d", m, sec)
    }
}

struct HangUpIcon: View {
    var width: CGFloat = 66
    var body: some View {
        let h = width * 0.25
        let s = width / 66
        return Path { p in
            p.move(to: CGPoint(x: 3 * s, y: 5.4 * s))
            p.addQuadCurve(to: CGPoint(x: 63 * s, y: 5.4 * s),
                           control: CGPoint(x: 33 * s, y: 0.4 * s))
            p.addLine(to: CGPoint(x: 63 * s, y: 9.2 * s))
            p.addQuadCurve(to: CGPoint(x: 43 * s, y: 13.2 * s),
                           control: CGPoint(x: 53 * s, y: 13.4 * s))
            p.addLine(to: CGPoint(x: 23 * s, y: 13.2 * s))
            p.addQuadCurve(to: CGPoint(x: 3 * s, y: 9.2 * s),
                           control: CGPoint(x: 13 * s, y: 13.4 * s))
            p.closeSubpath()
        }
        .fill(Color.white)
        .frame(width: width, height: max(8, h))
    }
}

struct PipIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let line = max(1.4, w * 0.09)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: w * 0.16, style: .continuous)
                    .stroke(Color.white, lineWidth: line)
                    .frame(width: w * 0.86, height: h * 0.86)
                RoundedRectangle(cornerRadius: w * 0.12, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                    .overlay(RoundedRectangle(cornerRadius: w * 0.12, style: .continuous)
                        .stroke(Color.white, lineWidth: line))
                    .frame(width: w * 0.52, height: h * 0.40)
                    .offset(x: w * 0.48, y: h * 0.60)
            }
        }
    }
}

struct PlusIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Path { p in
                p.move(to: CGPoint(x: 0, y: w / 2))
                p.addLine(to: CGPoint(x: w, y: w / 2))
                p.move(to: CGPoint(x: w / 2, y: 0))
                p.addLine(to: CGPoint(x: w / 2, y: w))
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: max(1.6, w * 0.11), lineCap: .round))
        }
    }
}

struct CallIcon: View {
    let key: String
    var symbol: String = "circle"
    var builtin: String? = nil
    var size: CGFloat = 24
    var color: Color = .white

    var body: some View {
        if let v = IconOverrides.custom(key), !v.isEmpty {
            if v.hasPrefix("<svg") {
                SVGIcon(markup: v, size: size, color: color)
            } else if v.hasPrefix("http") || v.hasPrefix("/uploads") || v.hasPrefix("data:") {
                RemoteImage(path: v).frame(width: size, height: size)
            } else {
                Text(v)
                    .font(pfStyled(size: size * 0.9))
                    .foregroundColor(color)
                    .frame(width: size, height: size)
            }
        } else if let b = builtin {
            SVGIcon(markup: b, size: size, color: color)
        } else {
            Image(systemName: symbol)
                .font(.system(size: size * 0.9, weight: .medium))
                .foregroundColor(color)
                .frame(width: size, height: size)
        }
    }
}

struct MarqueeText: View {
    let text: String
    var size: CGFloat = 15
    var duration: Double = 7
    @State private var x: CGFloat = 0
    @State private var ready = false

    var body: some View {
        GeometryReader { geo in
            Text(text)
                .font(pfExact(size))
                .foregroundColor(.white.opacity(0.72))
                .fixedSize()
                .offset(x: x)
                .onAppear {
                    guard !ready else { return }
                    ready = true
                    x = geo.size.width
                    withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                        x = -geo.size.width
                    }
                }
        }
        .frame(height: size + 6)
    }
}

struct VideoSurface: UIViewRepresentable {
    let track: RTCVideoTrack?

    final class Holder {
        var attached: RTCVideoTrack?
    }

    func makeCoordinator() -> Holder { Holder() }

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let v = RTCMTLVideoView()
        v.videoContentMode = .scaleAspectFill
        v.clipsToBounds = true
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ view: RTCMTLVideoView, context: Context) {
        if context.coordinator.attached === track { return }
        context.coordinator.attached?.remove(view)
        context.coordinator.attached = track
        track?.add(view)
    }

    static func dismantleUIView(_ view: RTCMTLVideoView, coordinator: Holder) {
        coordinator.attached?.remove(view)
    }
}
