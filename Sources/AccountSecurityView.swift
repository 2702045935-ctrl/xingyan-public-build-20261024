import SwiftUI

struct AccountSecurityView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var realNameText = ""
    @State private var realNameVerified = false
    @State private var hasPay = false
    @State private var gestureOn = GestureStore.enabled
    @State private var voiceOn = VoiceLockStore.enabled
    @State private var showChangePwd = false
    @State private var confirmLogoutOthers = false

    @State private var showSafety = false

    private var me: User? { app.me }
    private var phoneText: String {
        let p = (me?.phone ?? "").trimmingCharacters(in: .whitespaces)
        return p.isEmpty ? Tr("未绑定") : maskPhone(p)
    }
    private var usernameText: String {
        let u = (me?.username ?? "").trimmingCharacters(in: .whitespaces)
        return u.isEmpty ? "—" : u
    }

    private var enabledProtectionCount: Int {
        (realNameVerified ? 1 : 0)
            + (hasPay ? 1 : 0)
            + (gestureOn ? 1 : 0)
            + (voiceOn ? 1 : 0)
    }

    private var protectionProgress: Double {
        Double(enabledProtectionCount) / 4
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("账号与安全"), back: { dismiss() })

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 24) {
                    securityOverview

                    securitySection(
                        title: Tr("账号与登录"),
                        footer: Tr("账号信息用于登录、找回密码和身份核验。")
                    ) {
                        accountInfoRow(
                            title: Tr("账号"),
                            detail: Tr("用于登录与找回账号"),
                            value: usernameText,
                            symbol: "person.text.rectangle.fill",
                            tint: Color(hex: 0x3478F6)
                        ) {
                            app.show(Tr("账号一年只能改一次，需要的话联系客服"))
                        }
                        rowDivider
                        accountInfoRow(
                            title: Tr("手机号"),
                            detail: Tr("用于安全验证与找回密码"),
                            value: phoneText,
                            symbol: "iphone.gen3",
                            tint: Color(hex: 0x34C759)
                        ) {
                            app.show(Tr("手机号在注册或找回密码时绑定，需要换号联系客服"))
                        }
                        rowDivider
                        NavigationLink {
                            ChangePasswordSheet()
                        } label: {
                            securityRow(
                                title: Tr("修改登录密码"),
                                detail: Tr("定期更新可以降低账号风险"),
                                symbol: "key.fill",
                                tint: Color(hex: 0xFF9F0A)
                            )
                        }
                        .buttonStyle(MenuPressStyle())
                    }

                    securitySection(
                        title: Tr("身份与支付"),
                        footer: Tr("实名信息和支付密码只用于安全核验，不会展示给其他用户。")
                    ) {
                        NavigationLink {
                            RealNameView()
                        } label: {
                            securityRow(
                                title: Tr("实名认证"),
                                detail: Tr("用于找回账号和资金安全验证"),
                                value: realNameText,
                                symbol: "person.crop.rectangle.badge.checkmark",
                                tint: Color(hex: 0x34C759)
                            )
                        }
                        .buttonStyle(MenuPressStyle())
                        rowDivider
                        NavigationLink {
                            PayPasswordView()
                        } label: {
                            securityRow(
                                title: Tr("支付密码"),
                                detail: Tr("转账和消费前验证"),
                                value: hasPay ? Tr("已设置") : Tr("未设置"),
                                symbol: "creditcard.fill",
                                tint: Color(hex: 0x3478F6)
                            )
                        }
                        .buttonStyle(MenuPressStyle())
                        rowDivider
                        accountInfoRow(
                            title: Tr("安全中心"),
                            detail: Tr("冻结 / 解冻 / 自助解封"),
                            value: "",
                            symbol: "shield.lefthalf.filled",
                            tint: Color(hex: 0x5E5CE6)
                        ) {
                            showSafety = true
                        }
                    }

                    securitySection(
                        title: Tr("应用保护"),
                        footer: Tr("安全锁只保存在本机，用于防止他人直接打开 Luchat。")
                    ) {
                        NavigationLink {
                            GestureSetupView()
                        } label: {
                            securityRow(
                                title: Tr("安全锁（手势密码）"),
                                detail: Tr("打开应用时要求验证"),
                                value: gestureOn ? Tr("已开启") : Tr("未开启"),
                                symbol: "hand.draw.fill",
                                tint: Color(hex: 0xAF52DE)
                            )
                        }
                        .buttonStyle(MenuPressStyle())
                        rowDivider
                        NavigationLink {
                            VoiceLockSetupView()
                        } label: {
                            securityRow(
                                title: Tr("声音锁"),
                                detail: Tr("使用本人声音验证"),
                                value: voiceOn ? Tr("已开启") : Tr("未开启"),
                                symbol: "waveform.circle.fill",
                                tint: Color(hex: 0xFF375F)
                            )
                        }
                        .buttonStyle(MenuPressStyle())
                        rowDivider
                        NavigationLink {
                            SecurityScoreView()
                        } label: {
                            securityRow(
                                title: Tr("安全分"),
                                detail: Tr("查看账号安全建议"),
                                value: "\(enabledProtectionCount)/4",
                                symbol: "chart.bar.fill",
                                tint: Color(hex: 0x30B0C7)
                            )
                        }
                        .buttonStyle(MenuPressStyle())
                    }

                    securitySection(
                        title: Tr("登录设备"),
                        footer: Tr("退出其他设备以后，别的手机上登录的这个账号会被踢下线，需要重新登录。")
                    ) {
                        NavigationLink {
                            LoginDevicesView()
                        } label: {
                            securityRow(
                                title: Tr("登录设备管理"),
                                detail: Tr("查看并管理已登录设备"),
                                symbol: "laptopcomputer.and.iphone",
                                tint: Color(hex: 0x3478F6)
                            )
                        }
                        .buttonStyle(MenuPressStyle())
                        rowDivider
                        Button(role: .destructive) {
                            confirmLogoutOthers = true
                        } label: {
                            securityRow(
                                title: Tr("退出其他设备"),
                                detail: "",
                                symbol: "rectangle.portrait.and.arrow.right",
                                tint: C.red,
                                titleColor: C.red,
                                showsChevron: false
                            )
                        }
                        .buttonStyle(MenuPressStyle())
                    }

                    securitySection(
                        title: Tr("安全学习"),
                        footer: Tr("学习验证码、假客服、投资诈骗、屏幕共享和隐私权限等安全知识。")
                    ) {
                        NavigationLink {
                            SecurityAcademyView()
                        } label: {
                            securityRow(
                                title: Tr("安全学院"),
                                detail: Tr("反诈 / 账号 / 隐私"),
                                symbol: "graduationcap.fill",
                                tint: Color(hex: 0xFF9F0A)
                            )
                        }
                        .buttonStyle(MenuPressStyle())
                    }

                    Color.clear.frame(height: max(28, L.safeBottom + 12))
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()

        .sheet(isPresented: $showSafety) {
            AccountSafetyCenterView().environmentObject(app)
                .presentationDetents([.fraction(0.88), .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            refreshLocalStatus()
            Task { await refreshAccountStatus() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .chrisUIPrefsChanged)) { _ in
            refreshLocalStatus()
        }
        .confirmationDialog(Tr("退出其他设备？"), isPresented: $confirmLogoutOthers, titleVisibility: .visible) {
            Button(Tr("退出"), role: .destructive) {
                Task {
                    if let err = await API.shared.logoutOtherDevices() {
                        app.show(err)
                    } else {
                        app.show(Tr("已退出其他设备"))
                    }
                }
            }
            Button(Tr("取消"), role: .cancel) { }
        }
    }

    private func refreshLocalStatus() {
        gestureOn = GestureStore.enabled
        voiceOn = VoiceLockStore.enabled
    }

    private func refreshAccountStatus() async {
        if let m = try? await API.shared.me() {
            app.me = m
        }
        let rn = await API.shared.realNameStatus()
        realNameVerified = rn.verified
        realNameText = rn.verified ? Tr("已实名") : Tr("未实名")
        hasPay = await API.shared.hasPayPassword()
        refreshLocalStatus()
    }

    private var securityOverview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0x3478F6), Color(hex: 0x2558C8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text(Tr("账号保护"))
                        .font(pf(18, .semibold))
                        .foregroundColor(C.label)
                    Text(enabledProtectionCount == 4
                         ? Tr("所有保护项均已开启")
                         : Tr("已开启") + " \(enabledProtectionCount)/4 " + Tr("项保护"))
                        .font(pf(12.5))
                        .foregroundColor(C.subLabel)
                }

                Spacer(minLength: 8)

                Text("\(Int(protectionProgress * 100))%")
                    .font(pfMoney(17, .semibold))
                    .foregroundColor(enabledProtectionCount == 4 ? C.green : C.link)
                    .monospacedDigit()
            }

            ProgressView(value: protectionProgress)
                .tint(enabledProtectionCount == 4 ? C.green : C.link)

            Text(Tr("建议开启实名认证、支付密码和应用安全锁，降低账号与资金风险。"))
                .font(pf(11.5))
                .foregroundColor(C.subLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(C.cardBg,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(C.hairline, lineWidth: 0.7)
        }
    }

    private func securitySection<Content: View>(
        title: String,
        footer: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(pf(13, .semibold))
                .foregroundColor(C.subLabel)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(C.cardBg,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(C.hairline, lineWidth: 0.7)
            }

            if !footer.isEmpty {
                Text(footer)
                    .font(pf(11.5))
                    .foregroundColor(C.subLabel)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var rowDivider: some View {
        HairLine(inset: 66)
    }

    private func accountInfoRow(
        title: String,
        detail: String,
        value: String,
        symbol: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            securityRow(
                title: title,
                detail: detail,
                value: value,
                symbol: symbol,
                tint: tint
            )
        }
        .buttonStyle(MenuPressStyle())
    }

    private func securityRow(
        title: String,
        detail: String,
        value: String = "",
        symbol: String,
        tint: Color,
        titleColor: Color = C.label,
        showsChevron: Bool = true
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 10,
                                                 style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(pf(15.5))
                    .foregroundColor(titleColor)
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail)
                        .font(pf(11.5))
                        .foregroundColor(C.subLabel)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if !value.isEmpty {
                Text(value)
                    .font(pf(13.5))
                    .foregroundColor(C.subLabel)
                    .lineLimit(1)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(C.subLabel.opacity(0.72))
            }
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 62)
        .contentShape(Rectangle())
    }
}

struct ChangePasswordSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var next = ""
    @State private var again = ""
    @State private var busy = false
    @State private var errorText = ""

    var body: some View {
        List {
            Section {
                field(Tr("当前密码"), $current)
                field(Tr("新密码（至少 6 位）"), $next)
                field(Tr("再输一遍新密码"), $again)
            } footer: {
                if !errorText.isEmpty {
                    Text(errorText)
                        .foregroundStyle(.red)
                } else {
                    Text(Tr("改完密码以后，其他手机上登录的这个账号会被踢下线。"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("修改登录密码"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(busy ? Tr("保存中…") : Tr("完成")) {
                    save()
                }
                .disabled(!canSave)
            }
        }
        .hidesTabBar()
    }

    private var canSave: Bool { !busy && !current.isEmpty && next.count >= 6 && next == again }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            SecureField("", text: text)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func save() {
        errorText = ""
        if next != again { errorText = Tr("两次输入的新密码不一样"); return }
        if next.count < 6 { errorText = Tr("新密码至少 6 位"); return }
        busy = true
        Task {
            do {
                try await API.shared.changePassword(current: current, new: next)
                // 服务端会返回新的当前设备会话令牌；立即写回本机账号，
                // 否则切号页仍保存旧令牌，要退出页面/重开 App 才恢复正常。
                app.rememberLastUser()
                busy = false
                dismiss()
                app.show(Tr("密码已修改"))
            } catch {
                busy = false
                errorText = (error as? APIError)?.errorDescription ?? Tr("修改失败")
            }
        }
    }
}
