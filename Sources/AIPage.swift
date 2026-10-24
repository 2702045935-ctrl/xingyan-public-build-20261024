import SwiftUI
import UniformTypeIdentifiers

struct AIPageView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var wallet: AIWalletStatus?
    @State private var loading = true
    @State private var prompt = ""
    @State private var selectedPlan: AITokenPlan?
    @State private var route: AIRoute?
    @State private var callChat: Chat?
    @State private var uploadChat: Chat?
    @State private var showFilePicker = false
    @State private var uploading = false
    @State private var loadError = ""
    @FocusState private var inputFocused: Bool

    private let accent = Color(hex: 0x356FF4)

    private var modelName: String {
        let value = wallet?.model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "小星 Pro" : value
    }

    private var tokenText: String {
        Self.compactTokens(wallet?.tokens ?? 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("小星"), back: { dismiss() }) {
                HStack(spacing: 8) {
                    Button {
                        openCall()
                    } label: {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(accent)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(accent.opacity(0.12)))
                    }
                    .buttonStyle(.plain)

                    Text(tokenText)
                        .font(pf(11.5, .medium))
                        .foregroundColor(C.subLabel)
                        .frame(minWidth: 38, alignment: .trailing)
                }
            }

            if loading {
                VStack(spacing: 12) {
                    ProgressView().tint(accent)
                    Text(Tr("正在连接小星"))
                        .font(pf(12.5))
                        .foregroundColor(C.subLabel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if wallet == nil {
                unavailable
            } else {
                content
            }
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task { await load() }
        .sheet(item: $selectedPlan) { plan in
            BuyAITokensSheet(plan: plan, accent: accent) { result in
                if var current = wallet {
                    current.tokens = result.tokens
                    wallet = current
                }
                Task { await load(showLoading: false) }
            }
            .environmentObject(app)
        }
        .fullScreenCover(item: $route, onDismiss: {
            Task { await load(showLoading: false) }
        }) { item in
            BotChatView(chat: item.chat,
                        initialText: item.initialText,
                        autoSendInitial: item.autoSend)
                .environmentObject(app)
        }
        .fullScreenCover(item: $callChat) {
            AICallView(chat: $0)
                .environmentObject(app)
        }
        .fileImporter(isPresented: $showFilePicker,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { uploadFile(url) }
            case .failure:
                app.show(Tr("没有选中文件"))
            }
        }
        .overlay {
            if uploading {
                ZStack {
                    Color.black.opacity(0.14).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().tint(accent)
                        Text(Tr("正在上传文件…"))
                            .font(pf(13))
                            .foregroundColor(C.label)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .background(C.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
                }
            }
        }
    }

    private var unavailable: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .medium))
                .foregroundColor(accent)
            Text(Tr("小星服务暂时不可用"))
                .font(pf(17, .semibold))
                .foregroundColor(C.label)
            Text(loadError.isEmpty ? Tr("请检查网络后再试") : loadError)
                .font(pf(13))
                .foregroundColor(C.subLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Button(Tr("重新加载")) {
                Task { await load() }
            }
            .font(pf(14, .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .frame(height: 40)
            .background(Capsule().fill(accent))
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                hero
                composer
                tokenBar

                HStack {
                    Text(Tr("可以从这里开始"))
                        .font(pf(15, .semibold))
                        .foregroundColor(C.label)
                    Spacer()
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10)],
                          spacing: 10) {
                    ForEach(quickActions) { action in
                        quickActionCard(action)
                    }
                }

                if let plans = wallet?.plans, !plans.isEmpty {
                    planSection(plans)
                }

                if let purchases = wallet?.purchases, !purchases.isEmpty {
                    purchaseSection(purchases)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 36)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(C.pageBg)
        .contentShape(Rectangle())
        .onTapGesture { inputFocused = false }
    }

    private var hero: some View {
        VStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x4A8BFF),
                                                  Color(hex: 0x7B61FF)],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .frame(width: 56, height: 56)
                    .shadow(color: accent.opacity(0.22), radius: 16, y: 7)
                Image(systemName: "sparkles")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundColor(.white)
            }

            Text(Tr("你好，我是小星"))
                .font(pf(27, .bold))
                .foregroundColor(C.label)
            Text(modelName)
                .font(pf(10, .medium))
                .foregroundColor(accent)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(accent.opacity(0.09)))
            Text(Tr("有什么可以帮你？"))
                .font(pf(16))
                .foregroundColor(C.subLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 2)
    }

    private var composer: some View {
        VStack(spacing: 12) {
            TextField(Tr("有什么可以帮你？"), text: $prompt, axis: .vertical)
                .font(pf(16))
                .foregroundColor(C.label)
                .lineLimit(2...5)
                .focused($inputFocused)
                .padding(.top, 5)

            HStack(spacing: 8) {
                composerChip("⌘ " + Tr("功能")) {
                    inputFocused = true
                }
                composerChip(Tr("联网")) {
                    if !prompt.contains(Tr("联网搜索")) {
                        prompt = Tr("请联网搜索并告诉我：") + prompt
                    }
                    inputFocused = true
                }
                Spacer(minLength: 0)
                Button {
                    sendPrompt(prompt)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(canSend ? accent : accent.opacity(0.34)))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
        }
        .padding(16)
        .background(C.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(C.hairline.opacity(0.8), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.06), radius: 20, y: 8)
    }

    private var canSend: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func composerChip(_ title: String, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(title)
                .font(pf(11.5, .medium))
                .foregroundColor(Color(hex: 0x4E6D96))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(accent.opacity(0.09)))
        }
        .buttonStyle(.plain)
    }

    private var tokenBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Tr("Token 额度"))
                    .font(pf(10.5))
                    .foregroundColor(C.subLabel)
                Text(tokenText + " " + Tr("可用"))
                    .font(pf(14, .semibold))
                    .foregroundColor(C.label)
            }
            Spacer(minLength: 0)
            Button {
                if let plans = wallet?.plans, !plans.isEmpty {
                    selectedPlan = plans.count > 1 ? plans[1] : plans[0]
                }
            } label: {
                Text(Tr("购买"))
                    .font(pf(12, .medium))
                    .foregroundColor(accent)
                    .padding(.horizontal, 13)
                    .frame(height: 30)
                    .background(Capsule().fill(accent.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .disabled(wallet?.plans.isEmpty != false)
        }
        .padding(14)
        .background(C.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(C.hairline.opacity(0.75), lineWidth: 0.6))
    }

    private var quickActions: [AIQuickAction] {
        [
            .init(id: "write", icon: "square.and.pencil", title: Tr("帮我写作"),
                  subtitle: Tr("文案、总结、润色"), prompt: Tr("帮我写一段自然的文案："), attach: false),
            .init(id: "brainstorm", icon: "lightbulb.fill", title: Tr("头脑风暴"),
                  subtitle: Tr("想点子、做规划"), prompt: Tr("帮我想几个关于这件事的思路："), attach: false),
            .init(id: "search", icon: "globe", title: Tr("联网搜索"),
                  subtitle: Tr("查资料、看最新信息"), prompt: Tr("请联网搜索并告诉我："), attach: false),
            .init(id: "file", icon: "doc.text.fill", title: Tr("阅读文件"),
                  subtitle: Tr("总结文档和资料"), prompt: Tr("请阅读并总结我发送的文件。"), attach: true)
        ]
    }

    private func quickActionCard(_ action: AIQuickAction) -> some View {
        Button {
            if action.attach {
                openFileFlow(mode: action)
            } else {
                sendPrompt(action.prompt, autoSend: false)
            }
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: action.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(accent)
                        .frame(width: 22)
                    Text(action.title)
                        .font(pf(14, .medium))
                        .foregroundColor(C.label)
                    Spacer(minLength: 0)
                }
                Text(action.subtitle)
                    .font(pf(10.8))
                    .foregroundColor(C.subLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .background(C.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(C.hairline.opacity(0.8), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    private func planSection(_ plans: [AITokenPlan]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Tr("Token 套餐"))
                    .font(pf(15, .semibold))
                    .foregroundColor(C.label)
                Spacer()
                Text(Tr("额度实时到账"))
                    .font(pf(10.5))
                    .foregroundColor(C.subLabel)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(plans.enumerated()), id: \.element.id) { index, plan in
                        Button {
                            selectedPlan = plan
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(plan.name)
                                        .font(pf(14, .medium))
                                        .foregroundColor(C.label)
                                    Spacer(minLength: 8)
                                    if index == 1 || plan.tag == "recommended" {
                                        Text(Tr("推荐"))
                                            .font(pf(9, .medium))
                                            .foregroundColor(accent)
                                            .padding(.horizontal, 6)
                                            .frame(height: 18)
                                            .background(Capsule().fill(accent.opacity(0.10)))
                                    }
                                }
                                Text(Self.compactTokens(plan.granted) + " Token")
                                    .font(pf(12.5))
                                    .foregroundColor(C.subLabel)
                                HStack {
                                    Text("¥" + moneyFmt(plan.price))
                                        .font(pfMoney(19, .semibold))
                                        .foregroundColor(C.label)
                                    Spacer()
                                    Text(Tr("购买"))
                                        .font(pf(11.5, .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .frame(height: 28)
                                        .background(Capsule().fill(accent))
                                }
                            }
                            .padding(15)
                            .frame(width: 236, alignment: .leading)
                            .background(C.cardBg)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(index == 1 ? accent.opacity(0.48) : C.hairline.opacity(0.8),
                                        lineWidth: index == 1 ? 1 : 0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func purchaseSection(_ purchases: [AITokenPurchase]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Tr("最近购买"))
                .font(pf(14, .semibold))
                .foregroundColor(C.label)
            ForEach(purchases.prefix(5)) { item in
                HStack {
                    Text(item.name)
                        .font(pf(12.5))
                        .foregroundColor(C.subLabel)
                    Spacer()
                    Text("+ " + Self.compactTokens(item.granted))
                        .font(pf(12.5, .medium))
                        .foregroundColor(accent)
                }
                .frame(height: 28)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(C.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
            .stroke(C.hairline.opacity(0.75), lineWidth: 0.6))
    }

    private func load(showLoading: Bool = true) async {
        if showLoading { loading = true }
        do {
            wallet = try await API.shared.aiWallet()
            loadError = ""
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func sendPrompt(_ raw: String, autoSend: Bool = true) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let chat = resolveBotChat() else { return }
        prompt = ""
        inputFocused = false
        route = AIRoute(chat: chat, initialText: text, autoSend: autoSend)
    }

    private func openFileFlow(mode: AIQuickAction) {
        guard let chat = resolveBotChat() else { return }
        uploadChat = chat
        prompt = mode.prompt
        showFilePicker = true
    }

    private func uploadFile(_ url: URL) {
        guard let chat = uploadChat else { return }
        uploading = true
        Task {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let staged = try await Task.detached(priority: .userInitiated) {
                    try FileUploadStaging.copyToTemporary(url)
                }.value
                defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }
                let values = try staged.resourceValues(forKeys: [.fileSizeKey, .nameKey])
                let bytes = values.fileSize ?? 0
                guard bytes > 0 else { throw APIError.message("读不到这个文件") }
                guard bytes <= 100 * 1024 * 1024 else {
                    throw APIError.message("这个文件超过 100MB，先压缩一下再发")
                }
                let name = values.name ?? (staged.lastPathComponent.isEmpty ? "file" : staged.lastPathComponent)
                let uploadedURL = try await API.shared.uploadBinaryFile(
                    staged, mime: "application/octet-stream",
                    skipTranscode: true, onProgress: { _ in })
                let safeName = name.replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: "\\", with: "")
                let content = "{\"url\":\"\(uploadedURL)\",\"name\":\"\(safeName)\",\"bytes\":\(bytes),\"mime\":\"\(UTType(filenameExtension: staged.pathExtension)?.preferredMIMEType ?? "application/octet-stream")\"}"
                _ = try await API.shared.send(chatId: chat.id, kind: "file", content: content)
                await MainActor.run {
                    uploading = false
                    uploadChat = nil
                    app.show(Tr("文件已发送，可以继续问小星"))
                    route = AIRoute(chat: chat, initialText: prompt, autoSend: true)
                    prompt = ""
                }
            } catch {
                await MainActor.run {
                    uploading = false
                    app.show((error as? LocalizedError)?.errorDescription ?? "文件发送失败")
                }
            }
        }
    }

    private func resolveBotChat() -> Chat? {
        if let chat = app.chats.first(where: {
            $0.bot == "housekeeper" || ($0.botRank == 0 && $0.type != "group")
        }) {
            return chat
        }
        app.show(Tr("小星正在准备中，请稍后再试"))
        Task { await app.loadChats() }
        return nil
    }

    private func openCall() {
        guard let chat = resolveBotChat() else { return }
        callChat = chat
    }

    private static func compactTokens(_ value: Int) -> String {
        let n = max(0, value)
        if n >= 1_000_000 {
            let v = Double(n) / 1_000_000
            return String(format: v >= 10 ? "%.0fM" : "%.1fM", v)
        }
        if n >= 1_000 {
            let v = Double(n) / 1_000
            return String(format: v >= 100 ? "%.0fK" : "%.1fK", v)
        }
        return String(n)
    }
}

private struct AIRoute: Identifiable {
    let id = UUID()
    let chat: Chat
    let initialText: String
    let autoSend: Bool
}

private struct AIQuickAction: Identifiable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let prompt: String
    let attach: Bool
}

private struct BuyAITokensSheet: View {
    let plan: AITokenPlan
    let accent: Color
    let onPaid: (AITokenPurchaseResult) -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var requestId = UUID().uuidString.lowercased()
    @State private var paying = false
    @State private var errorText = ""
    @FocusState private var focused: Bool

    private var valid: Bool { password.count == 6 && !paying }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(Tr("购买 Token"))
                    .font(pf(18, .semibold))
                    .foregroundColor(C.label)
                Spacer()
                Button(Tr("关闭")) { dismiss() }
                    .font(pf(13))
                    .foregroundColor(C.subLabel)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .frame(height: 58)

            VStack(alignment: .leading, spacing: 6) {
                Text(plan.name)
                    .font(pf(15, .medium))
                    .foregroundColor(C.label)
                Text(AIPageView.compactTokenValue(plan.granted) + " Token · ¥" + moneyFmt(plan.price))
                    .font(pf(12.5, .medium))
                    .foregroundColor(accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(accent.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .padding(.horizontal, 20)

            SecureField(Tr("输入 6 位支付密码"), text: $password)
                .keyboardType(.numberPad)
                .textContentType(.password)
                .focused($focused)
                .font(pf(17, .medium))
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(C.fieldBg)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .onChange(of: password) { value in
                    let clean = String(value.filter { $0 >= "0" && $0 <= "9" }.prefix(6))
                    if clean != value { password = clean }
                    errorText = ""
                }

            if !errorText.isEmpty {
                Text(errorText)
                    .font(pf(12.5))
                    .foregroundColor(C.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 9)
            }

            Button {
                pay()
            } label: {
                HStack(spacing: 8) {
                    if paying { ProgressView().tint(.white) }
                    Text(paying ? Tr("处理中…") : Tr("确认支付"))
                        .font(pf(14.5, .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(valid ? accent : accent.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .disabled(!valid)
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Text(Tr("Token 为虚拟数字权益，购买后立即到账，不支持退款。"))
                .font(pf(10.5))
                .foregroundColor(C.subLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 26)
                .padding(.top, 12)

            Spacer(minLength: 20)
        }
        .background(C.cardBg.ignoresSafeArea())
        .onAppear { focused = true }
    }

    private func pay() {
        guard valid else { return }
        paying = true
        errorText = ""
        Task {
            do {
                let result = try await API.shared.buyAITokens(planId: plan.id,
                                                              password: password,
                                                              requestId: requestId)
                await MainActor.run {
                    paying = false
                    onPaid(result)
                    app.show(Tr("Token 已到账"))
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    paying = false
                    errorText = (error as? LocalizedError)?.errorDescription ?? "购买失败，再试一次"
                }
            }
        }
    }
}

private extension AIPageView {
    static func compactTokenValue(_ value: Int) -> String {
        compactTokens(value)
    }
}
