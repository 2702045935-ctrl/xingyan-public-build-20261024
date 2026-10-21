import SwiftUI

struct AICallView: View {
    let chat: Chat

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var voice = VoiceEngine()

    @State private var phaseText = "正在接通小星"
    @State private var userText = ""
    @State private var aiText = ""
    @State private var transcriptVisible = false
    @State private var muted = false
    @State private var typingMode = false
    @State private var typedText = ""
    @State private var busy = false
    @State private var seconds = 0
    @State private var accessDenied = false

    @FocusState private var typedFocused: Bool

    private let ink = Color(hex: 0x1D2632)
    private let subInk = Color(hex: 0x657080)
    private let accent = Color(hex: 0x356FF4)

    var body: some View {
        ZStack {
            LinearGradient(colors: [
                Color(hex: 0xF8FAFD),
                Color(hex: 0xEEF4FB),
                Color(hex: 0xE9F8F5)
            ], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()

            atmosphericLight

            VStack(spacing: 0) {
                topBar
                conversationCenter
                bottomControls
            }
        }
        .task {
            await prepare()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                seconds += 1
            }
        }
        .onChange(of: voice.heard) { value in
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                userText = clean
                transcriptVisible = true
            }
        }
        .onDisappear {
            voice.stop()
            voice.stopSpeech()
        }
        .overlay {
            if accessDenied {
                ZStack {
                    Color.black.opacity(0.22).ignoresSafeArea()
                    VStack(spacing: 14) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(accent)
                        Text(Tr("语音通话需要标准包"))
                            .font(pf(18, .semibold))
                            .foregroundColor(ink)
                        Text(Tr("请回 AI 工作台，从小星设置进入套餐补充页。"))
                            .font(pf(12.5))
                            .foregroundColor(subInk)
                            .multilineTextAlignment(.center)
                        Button(Tr("返回")) { dismiss() }
                            .font(pf(14, .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 22)
                            .frame(height: 40)
                            .background(Capsule().fill(accent))
                            .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.16), radius: 22, y: 10)
                }
            }
        }
    }

    private var atmosphericLight: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0xC3D7F6).opacity(0.24))
                .frame(width: 430, height: 430)
                .blur(radius: 72)
                .offset(x: 165, y: -310)
            Circle()
                .fill(Color(hex: 0xB6E6DC).opacity(0.22))
                .frame(width: 390, height: 390)
                .blur(radius: 82)
                .offset(x: -175, y: 310)
            Circle()
                .fill(Color(hex: 0xD6CCF5).opacity(0.18))
                .frame(width: 230, height: 230)
                .blur(radius: 62)
                .offset(x: 190, y: 170)
        }
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack {
            Button {
                hangUp()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(ink)
                    .frame(width: 42, height: 42)
                    .background {
                        GlassBackground(shape: Circle(),
                                        opacity: 0.78,
                                        shadow: true,
                                        seed: 0.16)
                    }
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 1) {
                Text(chat.name)
                    .font(pf(14, .bold))
                    .foregroundColor(ink)
                    .lineLimit(1)
                Text(callTimeText)
                    .font(pf(9.5))
                    .foregroundColor(Color(hex: 0x77808C))
                    .monospacedDigit()
            }

            Spacer()

            Button {
                transcriptVisible.toggle()
            } label: {
                Text(Tr("字"))
                    .font(pf(12.5, .medium))
                    .foregroundColor(ink)
                    .frame(width: 42, height: 42)
                    .background {
                        GlassBackground(shape: Circle(),
                                        opacity: transcriptVisible ? 0.92 : 0.74,
                                        shadow: true,
                                        seed: 0.62)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 7)
    }

    private var conversationCenter: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .fill(Color(hex: 0xAFC9F4).opacity(0.26))
                    .frame(width: 246 + voice.level * 44,
                           height: 246 + voice.level * 44)
                    .blur(radius: 30)

                VoiceOrb(level: voice.listening ? voice.level : 0.16,
                         diameter: 224,
                         listening: voice.listening,
                         mode: orbMode)
                    .contentShape(Circle())
                    .onTapGesture {
                        tapOrb()
                    }
                    .scaleEffect(1 + voice.level * 0.035)
                    .animation(.easeOut(duration: 0.1), value: voice.level)
                    .shadow(color: Color(hex: 0x4E5A70).opacity(0.18),
                            radius: 34, y: 16)
            }
            .frame(width: 286, height: 286)

            Text(chat.name)
                .font(pf(26, .bold))
                .foregroundColor(ink)

            HStack(spacing: 7) {
                Circle()
                    .fill(busy ? Color(hex: 0xE5A339) : Color(hex: 0x6EAA8C))
                    .frame(width: 6, height: 6)
                Text(phaseText)
                    .font(pf(13))
                    .foregroundColor(Color(hex: 0x5F6976))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background {
                GlassBackground(shape: Capsule(),
                                opacity: 0.64,
                                shadow: false,
                                seed: 0.40)
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity)
    }

    private var bottomControls: some View {
        VStack(spacing: 13) {
            if transcriptVisible && (!userText.isEmpty || !aiText.isEmpty) {
                transcriptCard
            }

            if typingMode {
                HStack(spacing: 9) {
                    TextField(Tr("输入想问小星的话"), text: $typedText, axis: .vertical)
                        .font(pf(13.5))
                        .foregroundColor(ink)
                        .lineLimit(1...3)
                        .focused($typedFocused)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Color.white.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    Button {
                        sendTyped()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(canSendTyped
                                ? Color(hex: 0x252D38) : Color(hex: 0xC5CCD6)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSendTyped)
                }
                .padding(8)
                .background(Color.white.opacity(0.36))
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            }

            HStack(alignment: .top, spacing: 20) {
                controlButton(symbol: "doc.text.fill",
                              label: Tr("对话记录"),
                              active: transcriptVisible,
                              danger: false) {
                    transcriptVisible.toggle()
                }
                controlButton(symbol: muted ? "mic.slash.fill" : "mic.fill",
                              label: muted ? Tr("取消静音") : Tr("静音"),
                              active: muted,
                              danger: false) {
                    toggleMute()
                }
                controlButton(symbol: "message.fill",
                              label: typingMode ? Tr("收起") : Tr("打字"),
                              active: typingMode,
                              danger: false) {
                    toggleTyping()
                }
                controlButton(symbol: "phone.down.fill",
                              label: Tr("挂断"),
                              active: false,
                              danger: true) {
                    hangUp()
                }
            }
            .frame(maxWidth: .infinity)

            Text(Tr("内容由 AI 生成"))
                .font(pf(9))
                .foregroundColor(Color(hex: 0x8A939F))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, max(14, L.safeBottom))
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !userText.isEmpty {
                transcriptRow(label: Tr("你"),
                              text: userText,
                              labelColor: Color(hex: 0x657080),
                              labelBackground: Color.white.opacity(0.58),
                              ink: Color(hex: 0x2A3441),
                              maxLines: 3)
            }
            if !aiText.isEmpty {
                transcriptRow(label: chat.name,
                              text: aiText,
                              labelColor: Color(hex: 0x63518A),
                              labelBackground: Color(hex: 0xE4D8F2),
                              ink: Color(hex: 0x202A36),
                              maxLines: 5)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GlassBackground(shape: RoundedRectangle(cornerRadius: 18,
                                                    style: .continuous),
                            opacity: 0.78,
                            shadow: true,
                            seed: 0.30)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(Color.white.opacity(0.72), lineWidth: 0.7))
    }

    private func transcriptRow(label: String, text: String,
                               labelColor: Color, labelBackground: Color,
                               ink: Color, maxLines: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(pf(9.5))
                .foregroundColor(labelColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(labelBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(text)
                .font(pf(maxLines > 3 ? 13 : 12))
                .foregroundColor(ink)
                .lineSpacing(4)
                .lineLimit(maxLines)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func controlButton(symbol: String, label: String,
                               active: Bool, danger: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(danger || active ? .white : ink)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(
                        danger ? Color(hex: 0xD94E50)
                            : (active ? Color(hex: 0x202A35) : Color.white.opacity(0.46))
                    ))
                    .overlay(Circle().stroke(
                        danger ? Color.clear : Color.white.opacity(0.45),
                        lineWidth: 0.7
                    ))
                    .shadow(color: danger
                            ? Color(hex: 0xC83F45).opacity(0.22)
                            : Color(hex: 0x4E5A70).opacity(0.10),
                            radius: danger ? 18 : 12, y: 6)
                Text(label)
                    .font(pf(10))
                    .foregroundColor(Color(hex: 0x697483))
                    .lineLimit(1)
            }
            .frame(width: 62)
        }
        .buttonStyle(.plain)
    }

    private var callTimeText: String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var canSendTyped: Bool {
        !typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !busy
    }

    private var orbMode: VoiceOrbMode {
        if voice.listening { return .listening }
        if busy { return .thinking }
        if voice.outputting || phaseText.contains("回答") { return .speaking }
        if phaseText.contains("失败") || phaseText.contains("没") { return .failed }
        return .idle
    }

    private func prepare() async {
        guard let wallet = try? await API.shared.aiWallet() else {
            phaseText = "暂时无法确认套餐"
            return
        }
        voice.aiVoice = wallet.voice ?? ""
        guard wallet.voiceCall == true, wallet.tier != "starter" else {
            accessDenied = true
            phaseText = "语音通话需要标准包"
            return
        }
        let allowed = await withCheckedContinuation { continuation in
            voice.authorize { continuation.resume(returning: $0) }
        }
        guard allowed else {
            phaseText = "没给语音识别权限"
            return
        }
        phaseText = "已接通"
        startListening()
    }

    private func startListening() {
        guard !busy, !muted, !typingMode, !voice.outputting else { return }
        voice.start { text in
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return }
            userText = clean
            transcriptVisible = true
            ask(clean)
        }
    }

    private func tapOrb() {
        if voice.outputting {
            voice.stopSpeech()
            phaseText = "已接通"
            if !muted && !typingMode { startListening() }
            return
        }
        if voice.listening {
            voice.stop()
            phaseText = "已暂停聆听"
            return
        }
        if !busy && !muted && !typingMode {
            startListening()
        }
    }

    private func toggleMute() {
        muted.toggle()
        if muted {
            if voice.listening { voice.stop() }
            phaseText = "已静音"
        } else if !busy && !typingMode {
            phaseText = "已接通"
            startListening()
        }
    }

    private func toggleTyping() {
        if typingMode {
            typingMode = false
            typedFocused = false
            if !busy && !muted { startListening() }
            return
        }
        if voice.listening { voice.stop() }
        if voice.outputting { voice.stopSpeech() }
        typingMode = true
        phaseText = "正在打字"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            typedFocused = true
        }
    }

    private func sendTyped() {
        let text = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSendTyped, !text.isEmpty else { return }
        typedText = ""
        typingMode = false
        typedFocused = false
        userText = text
        transcriptVisible = true
        ask(text)
    }

    private func ask(_ text: String) {
        busy = true
        phaseText = "正在想一想"
        aiText = ""
        Task {
            let prior = try? await API.shared.messages(chatId: chat.id, limit: 4)
            let before = prior?.messages.last?.id ?? ""
            do {
                _ = try await API.shared.send(
                    chatId: chat.id,
                    kind: "text",
                    content: text,
                    clientId: UUID().uuidString.lowercased()
                )
            } catch {
                busy = false
                phaseText = "这次没有发出去"
                return
            }

            var answer: Message?
            for index in 0..<42 {
                let delay: UInt64 = index < 5 ? 220_000_000
                    : (index < 15 ? 420_000_000 : 800_000_000)
                try? await Task.sleep(nanoseconds: delay)
                if Task.isCancelled { return }
                let result = try? await API.shared.messages(chatId: chat.id, limit: 12)
                guard let rows = result?.messages else { continue }
                if let last = rows.last,
                   last.id != before,
                   last.senderId != app.me?.id,
                   (last.kind == nil || last.kind == "text"),
                   !last.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    answer = last
                    break
                }
            }

            busy = false
            guard let answer = answer else {
                phaseText = "小星这次没有及时回应"
                return
            }
            aiText = answer.body
            transcriptVisible = true
            phaseText = "小星正在回答"
            voice.speakCloud(answer.body) {
                if !muted && !typingMode {
                    phaseText = "你可以继续说话"
                    startListening()
                } else {
                    phaseText = typingMode ? "正在打字" : "已静音"
                }
            }
            await app.loadChats()
        }
    }

    private func hangUp() {
        voice.stop()
        voice.stopSpeech()
        dismiss()
    }
}
