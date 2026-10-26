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

    @AppStorage("qrInkStyle") private var inkID = QRInk.green.rawValue

    private var ink: QRInk { QRInk(rawValue: inkID) ?? .green }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("我的二维码"), back: { dismiss() })

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    VStack(spacing: 10) {
                        Avatar(path: avatar.isEmpty ? (app.me?.avatarPath ?? "") : avatar,
                               size: 62, radius: 31, circle: true, level: growth.shownLevel)
                        Text(name.isEmpty ? (app.me?.name ?? "") : name)
                            .font(pf(18, .medium))
                            .foregroundColor(C.label)
                            .lineLimit(1)
                        Text(Tr("星言号：") + (username.isEmpty ? "-" : username))
                            .font(pf(13))
                            .foregroundColor(C.subLabel)
                            .lineLimit(1)
                    }
                    .padding(.top, 22)
                    .padding(.bottom, 18)

                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                        if loading {
                            ProgressView()
                        } else if rows.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 22)).foregroundColor(C.subLabel)
                                Text(Tr("二维码生成失败，稍后再试"))
                                    .font(pf(13)).foregroundColor(C.subLabel)
                            }
                        } else {
                            QRCanvas(rows: rows, avatar: avatar, ink: ink.color)
                                .frame(width: 224, height: 224)
                        }
                    }
                    .frame(width: 264, height: 264)
                    .shadow(color: Color.black.opacity(0.07), radius: 10, y: 3)

                    Text(Tr("扫一扫上面的二维码，加我为朋友"))
                        .font(pf(13))
                        .foregroundColor(C.subLabel)
                        .padding(.top, 14)

                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            qrTile(icon: "square.and.arrow.down.on.square", title: Tr("面对面收照片和文件"),
                                   sub: Tr("对方扫码当面发给你")) { showFaceFile = true }
                            qrTile(icon: "yensign.circle", title: Tr("面对面收红包"),
                                   sub: Tr("出示收款码收红包")) { showPayCode = true }
                        }
                        HStack(spacing: 10) {
                            qrTile(icon: "paintpalette", title: Tr("换个样式"),
                                   sub: ink.name + Tr("色")) { showStyle = true }
                            qrTile(icon: "arrow.down.to.line", title: saved ? Tr("已存到相册") : Tr("保存到相册"),
                                   sub: Tr("存成图片发给别人")) { saveToAlbum() }
                        }
                    }
                    .padding(.top, 18)

                    Spacer().frame(height: 30)
                }
                .padding(.horizontal, 16)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()

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

    private func qrTile(icon: String, title: String, sub: String,
                        tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(C.green)
                    Text(title)
                        .font(pf(15, .medium))
                        .foregroundColor(C.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(sub)
                    .font(pf(11.5))
                    .foregroundColor(C.subLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .frame(height: 74)
            .background(C.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func saveToAlbum() {
        guard !rows.isEmpty else { return }
        let card = VStack(spacing: 16) {
            QRCanvas(rows: rows, avatar: avatar, ink: ink.color).frame(width: 520, height: 520)
                .padding(24)
                .background(RoundedRectangle(cornerRadius: 24).fill(Color.white))
            HStack(spacing: 16) {
                Avatar(path: avatar, size: 84, radius: 42, circle: true, level: growth.shownLevel)
                VStack(alignment: .leading, spacing: 6) {
                    Text(name).font(.system(size: 28, weight: .semibold)).foregroundColor(.black)
                    Text(Tr("星言号：") + username).font(.system(size: 20)).foregroundColor(.gray)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            Text(Tr("扫一扫，加我为好友")).font(.system(size: 20)).foregroundColor(.gray)
        }
        .padding(40)
        .frame(width: 640)
        .background(Color.white)
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
