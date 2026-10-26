import SwiftUI
import UIKit

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
    @State private var accountAvatar = ""
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
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    brandArea
                    Spacer().frame(height: 34)
                    modeSwitch
                    Spacer().frame(height: 18)

                    if mode == .phone {
                        phoneFields
                    } else {
                        passwordFields
                    }

                    Spacer().frame(height: 18)
                    actionArea
                    Spacer().frame(height: 20)
                    termsArea
                    Spacer(minLength: 36)
                }
                .padding(.top, 82)
                .padding(.horizontal, 22)
                .padding(.bottom, max(24, L.safeBottom))
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
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

    private var brandArea: some View {
        VStack(spacing: 0) {
            if !accountAvatar.isEmpty {
                RemoteImage(path: accountAvatar, icon: "person.fill", mode: .fill)
                    .frame(width: 78, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else if !logoPath.isEmpty {
                RemoteImage(path: logoPath, icon: "message.fill", mode: .fill)
                    .frame(width: 78, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else if let icon = AppIconImage.image {
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 78, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(C.green)
                        .frame(width: 78, height: 78)
                    Text("星")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 78, height: 78)
                }
            }

            Text(brandName)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.top, 18)

            Text(brandSubtitle)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private var modeSwitch: some View {
        Picker("", selection: $mode) {
            Text("验证码登录").tag(Mode.phone)
            Text("密码登录").tag(Mode.password)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 340)
        .onChange(of: mode) { _ in
            sliderTicket = ""
            message = ""
            hint = ""
        }
    }

    private var phoneFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("手机号")
                .font(pf(11.5, .semibold))
                .foregroundColor(C.subLabel)
                .tracking(0.35)

            HStack(spacing: 12) {
                Text("+86")
                    .font(pf(15.5, .medium))
                    .foregroundColor(C.label)
                Rectangle().fill(C.hairline).frame(width: 0.7, height: 20)
                TextField("请输入手机号", text: $phone)
                    .keyboardType(.numberPad)
                    .focused($focus, equals: .phone)
                    .font(pf(16))
                    .foregroundColor(C.label)
                    .tint(C.green)
                    .onChange(of: phone) { value in
                        phone = String(value.filter(\.isNumber).prefix(11))
                        message = ""
                    }
            }
            .frame(height: 54)
            .padding(.horizontal, 16)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if codeSent {
                HStack(spacing: 12) {
                    TextField("请输入 6 位验证码", text: $code)
                        .keyboardType(.numberPad)
                        .focused($focus, equals: .code)
                        .font(pf(16))
                        .foregroundColor(C.label)
                        .tint(C.green)
                        .onChange(of: code) { value in
                            code = String(value.filter(\.isNumber).prefix(6))
                            message = ""
                        }
                    Button(countdown > 0 ? "\(countdown) 秒" : "重新获取") {
                        if countdown == 0 { requestCode() }
                    }
                    .font(pf(12.5, .medium))
                    .foregroundColor(countdown > 0 ? C.time : C.green)
                    .disabled(countdown > 0)
                }
                .frame(height: 54)
                .padding(.horizontal, 16)
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .frame(maxWidth: 340)
    }

    private var passwordFields: some View {
        VStack(spacing: 10) {
            TextField("星言号", text: $user)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .user)
                .font(pf(16))
                .foregroundColor(C.label)
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))

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
                .font(pf(16))
                .foregroundColor(C.label)

                Button { showPassword.toggle() } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .foregroundColor(C.subLabel)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(maxWidth: 340)
    }

    private var actionArea: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Button("找回密码") { showReset = true }
                Button("自助解封") { showUnban = true }
                Spacer()
            }
            .font(pf(12.5))
            .foregroundColor(C.subLabel)
            .buttonStyle(.plain)
            .frame(maxWidth: 340)

            Button { primaryAction() } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(.white) }
                    Text(primaryTitle)
                        .font(pf(16.5, .semibold))
                }
                .foregroundColor(canPrimary ? .white : C.subLabel)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(canPrimary ? C.green : Color(uiColor: .tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .frame(maxWidth: 340)

            if !message.isEmpty {
                Text(message)
                    .font(pf(12.5))
                    .foregroundColor(C.red)
                    .frame(maxWidth: 340, alignment: .leading)
            } else if !hint.isEmpty {
                Text(hint)
                    .font(pf(12.5))
                    .foregroundColor(C.subLabel)
                    .frame(maxWidth: 340, alignment: .leading)
            }
        }
    }

    private var termsArea: some View {
        HStack(alignment: .center, spacing: 8) {
            Button { agreed.toggle() } label: {
                ZStack {
                    Circle()
                        .fill(agreed ? C.green : C.raisedBg)
                        .overlay(Circle().stroke(agreed ? C.green : C.time, lineWidth: 1.2))
                    if agreed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)

            Text(.init("我已阅读并同意 [《用户协议》](terms://0) 和 [《隐私政策》](terms://1)"))
                .font(pf(11.5))
                .foregroundColor(C.subLabel)
                .tint(C.green)
                .environment(\.openURL, OpenURLAction { url in
                    if url.scheme == "terms" {
                        termsKind = Int(url.host ?? "0") ?? 0
                        showTerms = true
                    }
                    return .handled
                })
        }
        .frame(maxWidth: 340, alignment: .leading)
    }

    private func loadBranding() {
        Task {
            guard let b = await API.shared.branding() else { return }

            let shared = b.harmonyLogin
            if let n = shared?.appName ?? b.login?.appName ?? b.appName, !n.isEmpty,
               n != "智信", n != "Luming" { brandName = n }
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
