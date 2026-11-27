import SwiftUI
import UIKit

extension Notification.Name {
    static let chrisOpenAccountSidebar = Notification.Name("chris.openAccountSidebar")
}

enum AccountSidebarMetrics {
    static let maxWidth: CGFloat = 320
    static let minimumTrailingReveal: CGFloat = 48
    static let contentPush: CGFloat = 44
    static let horizontal: CGFloat = 16
    static let rowHeight: CGFloat = 52
    static let sectionTitleHeight: CGFloat = 28
    static let profileHeight: CGFloat = 72
    static let avatarSize: CGFloat = 56
    static let textOrigin: CGFloat = 84
    static let cornerRadius: CGFloat = 24
}

private struct AccountSidebarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(
            AccountSidebarMetrics.cornerRadius,
            min(rect.width, rect.height) / 2
        )
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct AccountSidebarOverlay: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    let isOpen: Bool
    let onClose: () -> Void
    let onOpenProfile: () -> Void

    @GestureState private var dragTranslation: CGFloat = 0

    private var railChats: [Chat] {
        Array(app.chats.lazy.filter { chat in
            guard (chat.botRank ?? 9) < 9 else { return false }
            return !(chat.title ?? "").isEmpty
                || !(chat.avatar ?? "").isEmpty
                || chat.lastMessage != nil
        }.prefix(16))
    }

    var body: some View {
        GeometryReader { proxy in
            let width = min(
                AccountSidebarMetrics.maxWidth,
                max(240, proxy.size.width - AccountSidebarMetrics.minimumTrailingReveal)
            )

            ZStack(alignment: .leading) {
                Color.black
                    .opacity(isOpen ? (scheme == .dark ? 0.30 : 0.18) : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        close()
                    }

                AccountSidebarPanel(
                    onClose: close,
                    onOpenProfile: {
                        routeToProfile()
                    }
                )
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .offset(x: isOpen ? dragTranslation : -width - 24)
                .shadow(
                    color: .black.opacity(scheme == .dark ? 0.46 : 0.18),
                    radius: 24,
                    x: 8,
                    y: 0
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .updating($dragTranslation) { value, state, _ in
                            guard abs(value.translation.width)
                                > abs(value.translation.height) * 1.15
                            else { return }
                            state = min(0, value.translation.width)
                        }
                        .onEnded { value in
                            let horizontal = value.translation.width
                            let velocity = value.predictedEndTranslation.width
                            if horizontal < -72 || velocity < -520 {
                                close()
                            }
                        }
                )

                AccountSidebarConversationRail(
                    chats: railChats,
                    onSelect: openRailChat
                )
                .frame(width: AccountSidebarMetrics.minimumTrailingReveal)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .opacity(isOpen ? 1 : 0)
                .offset(x: isOpen ? 0 : AccountSidebarMetrics.minimumTrailingReveal)
                .scaleEffect(isOpen ? 1 : 0.96, anchor: .trailing)
                .zIndex(3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .allowsHitTesting(isOpen)
        .accessibilityHidden(!isOpen)
        .animation(.spring(response: 0.26, dampingFraction: 0.88), value: isOpen)
    }

    private func close() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        onClose()
    }

    private func routeToProfile() {
        UISelectionFeedbackGenerator().selectionChanged()
        onClose()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            onOpenProfile()
        }
    }

    private func openRailChat(_ chat: Chat) {
        UISelectionFeedbackGenerator().selectionChanged()
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            app.openChatViaList(chat)
        }
    }
}

private struct AccountSidebarConversationRail: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    let chats: [Chat]
    let onSelect: (Chat) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {
                ForEach(Array(chats.enumerated()), id: \.element.id) { index, chat in
                    Button {
                        onSelect(chat)
                    } label: {
                        Avatar(
                            path: avatarPath(chat),
                            size: 34,
                            radius: 17,
                            circle: true
                        )
                        .frame(width: 46, height: 46)
                        .overlay(alignment: .bottomTrailing) {
                            if index == 0 {
                                Circle()
                                    .fill(Color.dyn(0x0F8B65, 0x36CA95))
                                    .frame(width: 8, height: 8)
                                    .overlay(Circle().stroke(
                                        scheme == .dark ? Color(hex: 0x1A1A1A) : .white,
                                        lineWidth: 1.5
                                    ))
                                    .offset(x: -5, y: -5)
                            }
                        }
                        .contentShape(Circle())
                    }
                    .buttonStyle(MenuPressStyle())
                    .accessibilityLabel(chat.name)
                }
            }
            .padding(.vertical, 10)
        }
        .background {
            ZStack {
                Rectangle().fill(.regularMaterial)
                Rectangle().fill(
                    LinearGradient(
                        colors: [
                            Color.dyn(0x0F8B65, 0x36CA95)
                                .opacity(scheme == .dark ? 0.08 : 0.05),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            Rectangle().fill(
                scheme == .dark ? Color.black.opacity(0.20) : Color.white.opacity(0.34)
            )
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.primary.opacity(scheme == .dark ? 0.10 : 0.06))
                .frame(width: 0.5)
        }
        .accessibilityHidden(chats.isEmpty)
    }

    private func avatarPath(_ chat: Chat) -> String {
        let own = (chat.avatar ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !own.isEmpty { return own }
        guard (chat.type ?? "direct") == "direct" else { return "" }
        let peerId = (chat.memberIds ?? []).first { $0 != app.me?.id }
            ?? chat.lastMessage?.senderId
            ?? ""
        guard !peerId.isEmpty, peerId != app.me?.id else { return "" }
        return app.contact(for: peerId)?.avatarPath ?? ""
    }
}

private struct AccountSidebarPanel: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var lang = LangStore.shared

    let onClose: () -> Void
    let onOpenProfile: () -> Void

    @State private var showAccounts = false
    @State private var showQR = false
    @State private var showFavorites = false
    @State private var showDevices = false
    @State private var showSettings = false
    @State private var showFeedback = false
    @State private var confirmLogout = false
    @State private var loggingOut = false

    private var primaryInk: Color { Color.dyn(0x17191C, 0xF3F4F4) }
    private var secondaryInk: Color { Color.dyn(0x737980, 0xA0A6AB) }
    private var tertiaryInk: Color { Color.dyn(0x969CA2, 0x70777D) }
    private var rule: Color { Color.dyn(0xE8EAED, 0x24282B) }
    private var accent: Color { Color.dyn(0x0F8B65, 0x36CA95) }
    private var danger: Color { Color.dyn(0xFF3B30, 0xFF453A) }
    private var panelTint: Color {
        scheme == .dark
            ? Color.black.opacity(0.42)
            : Color.white.opacity(0.62)
    }
    private var panelColorGlow: LinearGradient {
        LinearGradient(
            colors: scheme == .dark
                ? [
                    accent.opacity(0.07),
                    Color.clear,
                    Color.black.opacity(0.08)
                ]
                : [
                    accent.opacity(0.055),
                    Color.white.opacity(0.06),
                    Color.white.opacity(0.12)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var accountLine: String {
        let username = (app.me?.username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !username.isEmpty { return Tr("星言号") + " " + username }
        let phone = (app.me?.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return phone.isEmpty ? Tr("星言用户") : maskPhone(phone)
    }

    private var statusText: String {
        if app.offline { return Tr("离线") }
        if app.syncing { return Tr("同步中") }
        return Tr("在线")
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            profileButton
            if app.accounts.count > 1 {
                accountSwitchRow
            }
            sidebarRule
                .padding(.horizontal, AccountSidebarMetrics.horizontal)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    sectionTitle(Tr("快捷"))
                    actionRow(
                        title: Tr("我的二维码"),
                        symbol: "qrcode"
                    ) {
                        route {
                            showQR = true
                        }
                    }
                    actionRow(
                        title: Tr("收藏"),
                        symbol: "star"
                    ) {
                        route {
                            showFavorites = true
                        }
                    }

                    sectionTitle(Tr("管理"))
                    actionRow(
                        title: Tr("设备与同步"),
                        symbol: "iphone.gen3"
                    ) {
                        route {
                            showDevices = true
                        }
                    }
                    actionRow(
                        title: Tr("设置"),
                        symbol: "gearshape"
                    ) {
                        route {
                            showSettings = true
                        }
                    }
                }
                .padding(.bottom, 18)
            }
            .frame(maxHeight: .infinity)

            footer
        }
        .padding(.top, max(4, L.safeTop))
        .padding(.bottom, max(4, L.safeBottom))
        .background {
            ZStack {
                Rectangle().fill(.thinMaterial)
                Rectangle().fill(panelColorGlow)
                panelTint
            }
        }
        .clipShape(AccountSidebarShape())
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [
                    Color.white.opacity(scheme == .dark ? 0.05 : 0.56),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 1)
        }
        .sheet(isPresented: $showAccounts) {
            NavigationStack {
                SwitchAccountView()
                    .environmentObject(app)
            }
        }
        .fullScreenCover(isPresented: $showQR) {
            MyQRView()
                .environmentObject(app)
        }
        .fullScreenCover(isPresented: $showFavorites) {
            FavoritesView()
                .environmentObject(app)
        }
        .fullScreenCover(isPresented: $showDevices) {
            LoginDevicesView()
                .environmentObject(app)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                AppleSettingsView()
                    .environmentObject(app)
            }
        }
        .fullScreenCover(isPresented: $showFeedback) {
            SupportView()
                .environmentObject(app)
        }
        .alert(Tr("确定退出登录？"), isPresented: $confirmLogout) {
            Button(Tr("取消"), role: .cancel) { }
            Button(Tr("退出登录"), role: .destructive) {
                loggingOut = true
                Task { @MainActor in
                    await app.logout()
                    loggingOut = false
                    onClose()
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("星言")
                .font(pf(17, .semibold))
                .foregroundStyle(primaryInk)
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(secondaryInk)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(primaryInk.opacity(scheme == .dark ? 0.075 : 0.05))
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("关闭"))
        }
        .padding(.horizontal, AccountSidebarMetrics.horizontal)
        .frame(height: 44)
    }

    private var profileButton: some View {
        Button(action: onOpenProfile) {
            HStack(spacing: 12) {
                Avatar(
                    path: app.me?.avatarPath ?? "",
                    size: AccountSidebarMetrics.avatarSize,
                    radius: AccountSidebarMetrics.avatarSize / 2,
                    circle: true,
                    level: max(0, app.me?.qqLevel ?? 0)
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(app.me?.name ?? Tr("星言用户"))
                        .font(pf(17, .semibold))
                        .foregroundStyle(primaryInk)
                        .lineLimit(1)
                    Text(accountLine)
                        .font(pf(12.5))
                        .foregroundStyle(tertiaryInk)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(app.offline ? tertiaryInk : accent)
                            .frame(width: 6, height: 6)
                        Text(statusText)
                            .font(pf(12.5))
                            .foregroundStyle(secondaryInk)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tertiaryInk.opacity(0.72))
            }
            .padding(.horizontal, AccountSidebarMetrics.horizontal)
            .frame(height: AccountSidebarMetrics.profileHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(AccountSidebarPressStyle())
        .accessibilityLabel(Tr("打开个人资料"))
    }

    private var accountSwitchRow: some View {
        actionRow(
            title: Tr("切换账号"),
            symbol: "arrow.left.arrow.right.circle",
            trailing: "\(app.accounts.count)"
        ) {
            route {
                showAccounts = true
            }
        }
        .padding(.horizontal, 0)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            sidebarRule
                .padding(.horizontal, AccountSidebarMetrics.horizontal)
            actionRow(
                title: Tr("帮助与反馈"),
                symbol: "questionmark.circle"
            ) {
                route {
                    showFeedback = true
                }
            }
            sidebarRule
                .padding(.leading, 52)
                .padding(.trailing, AccountSidebarMetrics.horizontal)
            actionRow(
                title: loggingOut ? Tr("正在退出…") : Tr("退出登录"),
                symbol: "rectangle.portrait.and.arrow.right",
                destructive: true,
                showsChevron: false,
                busy: loggingOut
            ) {
                guard !loggingOut else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                confirmLogout = true
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(pf(12, .semibold))
            .foregroundStyle(secondaryInk)
            .padding(.leading, AccountSidebarMetrics.horizontal)
            .padding(.top, 20)
            .padding(.bottom, 8)
            .frame(height: AccountSidebarMetrics.sectionTitleHeight + 28, alignment: .bottomLeading)
    }

    private func actionRow(
        title: String,
        symbol: String,
        trailing: String? = nil,
        destructive: Bool = false,
        showsChevron: Bool = true,
        busy: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(destructive ? danger : secondaryInk)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                destructive
                                    ? danger.opacity(scheme == .dark ? 0.13 : 0.09)
                                    : primaryInk.opacity(scheme == .dark ? 0.075 : 0.05)
                            )
                    )

                Text(title)
                    .font(pf(15))
                    .foregroundStyle(destructive ? danger : primaryInk)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(secondaryInk)
                } else if let trailing {
                    Text(trailing)
                        .font(pf(12.5, .medium))
                        .foregroundStyle(tertiaryInk)
                        .monospacedDigit()
                }

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tertiaryInk.opacity(0.72))
                }
            }
            .padding(.horizontal, AccountSidebarMetrics.horizontal)
            .frame(height: AccountSidebarMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(AccountSidebarPressStyle())
    }

    private var sidebarRule: some View {
        Rectangle()
            .fill(rule)
            .frame(height: 0.5)
    }

    private func route(_ action: @escaping () -> Void) {
        UISelectionFeedbackGenerator().selectionChanged()
        onClose()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: action)
    }
}

private struct AccountSidebarPressStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Rectangle().fill(
                    Color.primary.opacity(
                        configuration.isPressed
                            ? (scheme == .dark ? 0.075 : 0.045)
                            : 0
                    )
                )
            )
            .animation(.easeOut(duration: 0.09), value: configuration.isPressed)
    }
}
