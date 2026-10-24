import SwiftUI

enum QRInk: String, CaseIterable {
    case green, blue, red, amber, purple, black

    var name: String {
        switch self {
        case .green:  return "绿"
        case .blue:   return "蓝"
        case .red:    return "红"
        case .amber:  return "黄"
        case .purple: return "紫"
        case .black:  return "黑"
        }
    }
    var color: Color {
        switch self {
        case .green:  return Color(hexString: "#12A05A")
        case .blue:   return Color(hexString: "#1B5FD0")
        case .red:    return Color(hexString: "#D6353B")
        case .amber:  return Color(hexString: "#B4770F")
        case .purple: return Color(hexString: "#6A3FD0")
        case .black:  return Color(hexString: "#111111")
        }
    }
}

struct MyQRView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var growth = GrowthStore.shared

    @State private var rows: [String] = []
    @State private var code = ""
    @State private var name = ""
    @State private var username = ""
    @State private var avatar = ""
    @State private var loading = true
    @State private var saved = false
    @State private var showScan = false

    @State private var showStyle = false

    @State private var showFaceFile = false

    @State private var showPayCode = false
    @State private var appeared = false

    @AppStorage("qrInkStyle") private var inkID = QRInk.green.rawValue

    private var ink: QRInk { QRInk(rawValue: inkID) ?? .green }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("个人名片"), back: { dismiss() })

            ZStack {
                PremiumProfileBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        PremiumGlassCard(radius: 30,
                                         tint: scheme == .dark ? C.green.opacity(0.05)
                                                               : Color.white.opacity(0.035)) {
                            VStack(spacing: 0) {
                                identityHeader

                                Rectangle()
                                    .fill(C.hairline)
                                    .frame(height: 0.5)
                                    .padding(.top, 18)

                                qrPanel
                                    .padding(.top, 18)

                                actionDock
                                    .padding(.top, 18)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 18)
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .opacity(appeared ? 1 : 0)
                        .scaleEffect(appeared ? 1 : 0.985)
                        .offset(y: appeared ? 0 : 8)

                        Spacer().frame(height: 30)
                    }
                }
            }
        }
        .background(PremiumProfileBackground())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                appeared = true
            }
        }

        .modifier(BrightenScreen())
        .fullScreenCover(isPresented: $showScan) {
            ScannerView { text in handleScanned(text, app: app) }
        }

        .sheet(isPresented: $showStyle) {
            QRStyleSheet(current: ink) { pick in
                inkID = pick.rawValue
                DiagLog.shared.note("二维码样式：" + pick.name)
            }
        }

        .sheet(isPresented: $showFaceFile) {
            FaceToFaceFileSheet(rows: rows, avatar: avatar, name: name, ink: ink.color)
                .environmentObject(app)
        }

        .sheet(isPresented: $showPayCode) {
            NavigationStack { PayCodePage() }
                .environmentObject(app)
        }
        .task {
            let r = await API.shared.myQRCode()
            code = r.code
            rows = r.rows
            name = r.user?.name ?? (app.me?.name ?? "")
            username = r.user?.username ?? (app.me?.username ?? "")
            avatar = r.user?.avatarPath ?? (app.me?.avatarPath ?? "")
            loading = false
        }
    }

    private var identityHeader: some View {
        HStack(spacing: 15) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [C.green.opacity(0.20),
                                                  Color.white.opacity(scheme == .dark ? 0.04 : 0.52)],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                Avatar(path: avatar.isEmpty ? (app.me?.avatarPath ?? "") : avatar,
                       size: 66, radius: 33, circle: true, level: growth.shownLevel)
                    .padding(4)
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 5) {
                Text(Tr("星言身份卡"))
                    .font(pf(10.5, .semibold))
                    .tracking(1.4)
                    .foregroundColor(C.green)

                Text(name.isEmpty ? (app.me?.name ?? "") : name)
                    .font(pf(22, .semibold))
                    .foregroundColor(C.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                HStack(spacing: 6) {
                    Text(Tr("星言号"))
                        .font(pf(11.5, .medium))
                        .foregroundColor(C.subLabel)
                    Text(username.isEmpty ? "-" : username)
                        .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                        .foregroundColor(C.label.opacity(0.80))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .copyOnLongPress(username) { app.show($0) }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var qrPanel: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white)
                if loading {
                    ProgressView()
                        .tint(C.green)
                } else if rows.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 22))
                            .foregroundColor(C.subLabel)
                        Text(Tr("二维码生成失败，稍后再试"))
                            .font(pf(13))
                            .foregroundColor(C.subLabel)
                    }
                } else {
                    QRCanvas(rows: rows, avatar: avatar, ink: ink.color)
                        .frame(width: 214, height: 214)
                }
            }
            .frame(width: 244, height: 244)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.92), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.30 : 0.10),
                    radius: 14, y: 7)

            VStack(spacing: 3) {
                Text(Tr("扫码添加好友"))
                    .font(pf(16, .semibold))
                    .foregroundColor(C.label)
                Text(Tr("打开星言 · 发现 · 扫一扫"))
                    .font(pf(11.5))
                    .tracking(0.2)
                    .foregroundColor(C.subLabel)
            }
        }
    }

    private var actionDock: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(C.hairline)
                .frame(height: 0.5)

            HStack(spacing: 0) {
                qrTile(icon: "square.and.arrow.down.on.square",
                       title: Tr("收照片和文件"),
                       sub: Tr("当面发送")) { showFaceFile = true }
                actionDivider
                qrTile(icon: "yensign.circle",
                       title: Tr("收红包"),
                       sub: Tr("当场收款")) { showPayCode = true }
            }

            Rectangle()
                .fill(C.hairline)
                .frame(height: 0.5)
                .padding(.horizontal, 10)

            HStack(spacing: 0) {
                qrTile(icon: "paintpalette",
                       title: Tr("名片样式"),
                       sub: ink.name + Tr("色")) { showStyle = true }
                actionDivider
                qrTile(icon: "arrow.down.to.line",
                       title: saved ? Tr("已保存") : Tr("保存名片"),
                       sub: Tr("保存到相册")) { saveToAlbum() }
            }
        }
    }

    private var actionDivider: some View {
        Rectangle()
            .fill(C.hairline)
            .frame(width: 0.5, height: 42)
    }

    private func qrTile(icon: String, title: String, sub: String,
                        tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(C.green.opacity(scheme == .dark ? 0.14 : 0.10))
                    Image(systemName: icon)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(C.green)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(pf(13.5, .medium))
                        .foregroundColor(C.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(sub)
                        .font(pf(10.5))
                        .foregroundColor(C.subLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(height: 70)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func saveToAlbum() {
        guard !rows.isEmpty else { return }
        let card = VStack(spacing: 20) {
            VStack(spacing: 5) {
                Text(Tr("星言身份卡"))
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(2.4)
                    .foregroundColor(Color(hex: 0x0A9F57))
                Text(name)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(Color(hex: 0x171817))
                Text(Tr("星言号") + "  " + username)
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(hex: 0x70736F))
            }

            QRCanvas(rows: rows, avatar: avatar, ink: ink.color).frame(width: 520, height: 520)
                .padding(24)
                .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color.white))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.black.opacity(0.045), lineWidth: 1)
                }

            VStack(spacing: 5) {
                Text(Tr("扫码添加好友"))
                    .font(.system(size: 19, weight: .medium))
                    .foregroundColor(Color(hex: 0x202220))
                HStack(spacing: 7) {
                    Circle()
                        .fill(Color(hex: 0x0A9F57))
                        .frame(width: 7, height: 7)
                    Text(Tr("星言 · 个人身份"))
                        .font(.system(size: 13, weight: .medium))
                        .tracking(0.8)
                        .foregroundColor(Color(hex: 0x858984))
                }
            }
        }
        .padding(.horizontal, 38)
        .padding(.vertical, 34)
        .frame(width: 640)
        .background(
            LinearGradient(colors: [Color(hex: 0xF9FCF9),
                                    Color(hex: 0xEEF6F0)],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        if let img = renderer.uiImage {
            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
            saved = true
            app.show(Tr("二维码已存到相册"))
            return
        }
        app.show(Tr("保存失败，可以截图"))
    }
}
