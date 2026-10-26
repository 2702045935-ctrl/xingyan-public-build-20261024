import SwiftUI
import UIKit

private enum LoginStyle {
    static let canvas = Color.dyn(0xF5F4F0, 0x080A09)
    static let surface = Color.dyn(0xFFFFFF, 0x111513)
    static let field = Color.dyn(0xECEAE4, 0x171B19)
    static let ink = Color.dyn(0x17201C, 0xEFF4F1)
    static let secondary = Color.dyn(0x626B66, 0xA8B2AD)
    static let tertiary = Color.dyn(0x929994, 0x727C77)
    static let divider = Color.dyn(0xE2DFD7, 0x232925)
    static let jade = Color.dyn(0x176A57, 0x63C6A5)
    static let jadeDeep = Color.dyn(0x0F4F41, 0x3B9C7E)
    static let gold = Color.dyn(0xC18A32, 0xE3B464)
}

struct HarmonyLoginView: View {
    @EnvironmentObject var app: AppState
    @FocusState private var focus: Field?

    private enum Field: Hashable { case phone, code, user, pass }
    private enum Mode { case phone, password }

    @State private var mode: Mode = .phone
    @State private var phone = UserDefaults.standard.string(forKey: "chris.lastPhone") ?? ""
    @State private var code = ""
    @State private var user = ""
    @State private var pass = ""
    @State private var busy = false
    @State private var codeSent = false
    @State private var countdown = 0
    @State private var agreed = false
    @State private var message = ""
    @State private var hint = ""
    @State private var brandName = "星言"
    @State private var brandSubtitle = "让每一句真心，都有回应"
    @State private var logoPath = ""
    @State private var showPassword = false
    @State private var sliderTicket = ""
    @State private var sliderSeed = 0
    @State private var showSlider = false
    @State private var showReset = false
    @State private var showUnban = false
    @State private var showTerms = false
    @State private var termsKind = 0
    @State private var countdownTask: Task<Void, Never>?

    private var validPhone: Bool {
        phone.range(of: #"^1[3-9]\d{9}$"#, options: .regularExpression) != nil
    }

    private var canPrimary: Bool {
        guard agreed, !busy else { return false }
        switch mode {
        case .password:
            return !user.trimmingCharacters(in: .whitespaces).isEmpty && !pass.isEmpty
        case .phone:
            if !validPhone { return false }
            return !codeSent || code.count == 6
        }
    }

    private var primaryTitle: String {
        if busy { return "请稍候…" }
        if mode == .password || codeSent { return "登录" }
        return "获取验证码"
    }

    var body: some View {
        ZStack {
            LoginStyle.canvas.ignoresSafeArea()
            orbitBackdrop

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    brandArea
                    Spacer().frame(height: 34)

                    VStack(spacing: 0) {
                        if mode == .phone {
                            phoneFields
                        } else {
                            passwordFields
                        }

                        Spacer().frame(height: 18)
                        actionArea

                        if !message.isEmpty || !hint.isEmpty {
                            Spacer().frame(height: 12)
                            Text(message.isEmpty ? hint : message)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(message.isEmpty ? LoginStyle.secondary : Color(hex: 0xD9534F))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 2)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: 364)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(LoginStyle.surface)
                            .shadow(color: Color.black.opacity(0.08), radius: 28, y: 16)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(LoginStyle.divider, lineWidth: 0.7)
                    )

                    Spacer().frame(height: 16)
                    termsArea
                    Spacer(minLength: 36)
                }
                .padding(.horizontal, 24)
                .padding(.top, 74)
                .padding(.bottom, max(24, L.safeBottom))
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(LoginStyle.canvas.ignoresSafeArea())
        .onAppear { loadBranding() }
        .onDisappear { countdownTask?.cancel() }
        .sheet(isPresented: $showSlider) {
            SliderSheet(freshKey: sliderSeed) { ticket in
                sliderTicket = ticket
                showSlider = false
                primaryAction()
            }
        }
        .sheet(isPresented: $showReset) { ResetPasswordSheet() }
        .sheet(isPresented: $showUnban) {
            UnbanSheet(preUser: user, prePass: pass)
        }
        .sheet(isPresented: $showTerms) { TermsSheet(kind: termsKind) }
    }

    private var orbitBackdrop: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .stroke(LoginStyle.jade.opacity(0.14), lineWidth: 1)
                    .frame(width: min(geo.size.width * 1.35, 540))
                    .offset(x: geo.size.width * 0.34, y: -geo.size.height * 0.32)
                Circle()
                    .stroke(LoginStyle.gold.opacity(0.12), lineWidth: 1)
                    .frame(width: min(geo.size.width * 0.76, 310))
                    .offset(x: -geo.size.width * 0.38, y: geo.size.height * 0.14)
                Circle()
                    .fill(LoginStyle.jade.opacity(0.08))
                    .frame(width: 8, height: 8)
                    .offset(x: geo.size.width * 0.31, y: -geo.size.height * 0.16)
                Circle()
                    .fill(LoginStyle.gold.opacity(0.55))
                    .frame(width: 5, height: 5)
                    .offset(x: -geo.size.width * 0.30, y: geo.size.height * 0.32)
            }
        }
        .allowsHitTesting(false)
    }

    private var brandArea: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .stroke(LoginStyle.jade.opacity(0.18), lineWidth: 1)
                    .frame(width: 104, height: 104)
                Circle()
                    .trim(from: 0.08, to: 0.62)
                    .stroke(LoginStyle.gold.opacity(0.75),
                            style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .rotationEffect(.degrees(-38))
                    .frame(width: 92, height: 92)

                if !logoPath.isEmpty {
                RemoteImage(path: logoPath, icon: "message.fill", mode: .fill)
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 0.7)
                    )
                } else {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(LinearGradient(colors: [LoginStyle.jade, LoginStyle.jadeDeep],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 76, height: 76)
                        .overlay(
                            Image(systemName: "sparkle")
                                .font(.system(size: 29, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.96))
                        )
                        .shadow(color: LoginStyle.jade.opacity(0.22), radius: 20, y: 10)
                }
            }
            .frame(width: 110, height: 110)

            Text(brandName)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(LoginStyle.ink)
                .tracking(5)
                .padding(.top, 4)

            Text(brandSubtitle)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(LoginStyle.secondary)
                .tracking(1.1)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private var phoneFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldTitle("手机号")

            HStack(spacing: 12) {
                Text("+86")
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(LoginStyle.ink)
                Rectangle().fill(LoginStyle.divider).frame(width: 0.7, height: 20)
                TextField("请输入手机号", text: $phone)
                    .keyboardType(.numberPad)
                    .focused($focus, equals: .phone)
                    .font(.system(size: 16.5))
                    .foregroundStyle(LoginStyle.ink)
                    .tint(LoginStyle.jade)
                    .onChange(of: phone) { value in
                        phone = String(value.filter(\.isNumber).prefix(11))
                        message = ""
                    }
            }
            .frame(height: 56)
            .padding(.horizontal, 18)
            .background(fieldShape.fill(LoginStyle.field))

            if codeSent {
                HStack(spacing: 12) {
                    TextField("请输入 6 位验证码", text: $code)
                        .keyboardType(.numberPad)
                        .focused($focus, equals: .code)
                        .font(.system(size: 16.5))
                        .foregroundStyle(LoginStyle.ink)
                        .tint(LoginStyle.jade)
                        .onChange(of: code) { value in
                            code = String(value.filter(\.isNumber).prefix(6))
                            message = ""
                        }
                    Button(countdown > 0 ? "\(countdown) 秒" : "重新获取") {
                        if countdown == 0 { requestCode() }
                    }
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(countdown > 0 ? LoginStyle.tertiary : LoginStyle.jade)
                    .disabled(countdown > 0)
                }
                .frame(height: 56)
                .padding(.horizontal, 18)
                .background(fieldShape.fill(LoginStyle.field))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var passwordFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldTitle("账号")
            HStack(spacing: 10) {
                Image(systemName: "person")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(LoginStyle.tertiary)
                TextField("账号或手机号", text: $user)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .user)
                    .font(.system(size: 16.5))
                    .foregroundStyle(LoginStyle.ink)
                    .tint(LoginStyle.jade)
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(fieldShape.fill(LoginStyle.field))

            fieldTitle("密码")
            HStack {
                Group {
                    if showPassword {
                        TextField("密码", text: $pass)
                    } else {
                        SecureField("密码", text: $pass)
                    }
                }
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .privacySensitive()
                .focused($focus, equals: .pass)
                .font(.system(size: 16.5))
                .foregroundStyle(LoginStyle.ink)
                .tint(LoginStyle.jade)

                Button { showPassword.toggle() } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .foregroundStyle(LoginStyle.tertiary)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(fieldShape.fill(LoginStyle.field))
        }
        .frame(maxWidth: .infinity)
    }

    private var actionArea: some View {
        VStack(spacing: 14) {
            HStack(spacing: 18) {
                Button("找回密码") { showReset = true }
                Button("自助解封") { showUnban = true }
                Spacer()
                Button(mode == .phone ? "密码登录 ›" : "验证码登录 ›") {
                    mode = mode == .phone ? .password : .phone
                    sliderTicket = ""
                    message = ""
                    hint = ""
                }
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(LoginStyle.secondary)
            .buttonStyle(.plain)

            Button { primaryAction() } label: {
                HStack(spacing: 8) {
                    if busy {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                    }
                    Text(primaryTitle)
                        .font(.system(size: 16, weight: .semibold))
                    if !busy {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12.5, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(canPrimary
                              ? AnyShapeStyle(LinearGradient(colors: [LoginStyle.jadeDeep, LoginStyle.jade],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                              : AnyShapeStyle(LoginStyle.jade.opacity(0.34)))
                )
                .shadow(color: canPrimary ? LoginStyle.jade.opacity(0.22) : .clear,
                        radius: 16, y: 8)
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
    }

    private var termsArea: some View {
        HStack(alignment: .center, spacing: 8) {
            Button { agreed.toggle() } label: {
                ZStack {
                    Circle()
                        .fill(agreed ? LoginStyle.jade : LoginStyle.surface)
                        .overlay(Circle().stroke(agreed ? LoginStyle.jade
                                                        : LoginStyle.tertiary, lineWidth: 1.1))
                    if agreed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)

            Text(.init("我已阅读并同意 [《用户协议》](terms://0) 和 [《隐私政策》](terms://1)"))
                .font(.system(size: 12.2))
                .foregroundStyle(LoginStyle.secondary)
                .tint(LoginStyle.jade)
                .environment(\.openURL, OpenURLAction { url in
                    if url.scheme == "terms" {
                        termsKind = Int(url.host ?? "0") ?? 0
                        showTerms = true
                    }
                    return .handled
                })
        }
        .frame(maxWidth: 364, alignment: .leading)
    }

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 17, style: .continuous)
    }

    private func fieldTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(LoginStyle.secondary)
            .tracking(0.5)
            .padding(.leading, 2)
    }

    private func loadBranding() {
        Task {
            guard let b = await API.shared.branding() else { return }

            let shared = b.harmonyLogin
            if let n = shared?.appName ?? b.login?.appName ?? b.appName, !n.isEmpty { brandName = n }
            if let s = shared?.subTitle ?? b.login?.subTitle, !s.isEmpty { brandSubtitle = s }
            if let l = shared?.logo ?? b.login?.logo ?? b.logo, !l.isEmpty { logoPath = l }
        }
    }

    private func requestCode() {
        guard agreed else {
            message = "请先阅读并同意用户协议和隐私政策"
            return
        }
        guard validPhone else {
            message = "请输入正确的 11 位手机号"
            return
        }
        busy = true
        message = ""
        hint = ""
        Task {
            do {
                let dev = try await API.shared.phoneCode(phone: phone)
                codeSent = true
                startCountdown()
                if let dev, !dev.isEmpty {
                    code = dev
                    hint = "开发环境验证码已自动填入"
                } else {
                    hint = "验证码已发送，5 分钟内有效"
                }
            } catch {
                message = (error as? APIError)?.errorDescription ?? "验证码没发出去"
            }
            busy = false
        }
    }

    private func primaryAction() {
        guard agreed else {
            message = "请先阅读并同意用户协议和隐私政策"
            return
        }
        if mode == .phone && !codeSent {
            requestCode()
        } else {
            login()
        }
    }

    private func login() {
        guard canPrimary || busy == false else { return }
        busy = true
        message = ""
        Task {
            do {
                if mode == .phone {
                    guard validPhone, code.count == 6 else {
                        throw APIError.message("请输入手机号和 6 位验证码")
                    }
                    try await app.login(phone: phone, code: code)
                    UserDefaults.standard.set(phone, forKey: "chris.lastPhone")
                } else {
                    let account = user.trimmingCharacters(in: .whitespaces)
                    guard !account.isEmpty, !pass.isEmpty else {
                        throw APIError.message("账号和密码都要填")
                    }
                    try await app.login(username: account, password: pass, sliderTicket: sliderTicket)
                }
            } catch APIError.needSlider {
                sliderTicket = ""
                sliderSeed += 1
                showSlider = true
            } catch {
                message = (error as? APIError)?.errorDescription ?? "登录失败"
            }
            busy = false
        }
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdown = 60
        countdownTask = Task { @MainActor in
            while countdown > 0, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                countdown -= 1
            }
        }
    }
}
