import SwiftUI

struct PluginsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var eyes = EyesStore.shared

    @State private var showEyes = false

    @State private var showFaceForEyes = false

    @State private var showBrowser = false

    @State private var showDrop = false

    @State private var showAI = false

    private var eyesValue: String {
        switch eyes.tier {
        case "off":    return Tr("已关闭")
        case "static": return Tr("静态")
        case "on":     return Tr("开启")
        default:       return ""
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("插件"), back: { dismiss() }) { }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    Button { showAI = true } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(LinearGradient(colors: [Color(hex: 0x4A8BFF),
                                                                      Color(hex: 0x7B61FF)],
                                                             startPoint: .topLeading,
                                                             endPoint: .bottomTrailing))
                                        .frame(width: 60, height: 60)
                                        .shadow(color: Color(hex: 0x356FF4).opacity(0.22),
                                                radius: 14, y: 6)
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 25, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 7) {
                                        Text(Tr("小星 AI"))
                                            .font(pf(21, .semibold))
                                            .foregroundColor(C.label)
                                        Text(Tr("已开启"))
                                            .font(pf(9.5, .medium))
                                            .foregroundColor(Color(hex: 0x2F6FED))
                                            .padding(.horizontal, 6)
                                            .frame(height: 18)
                                            .background(Capsule().fill(Color(hex: 0x2F6FED).opacity(0.10)))
                                    }
                                    Text(Tr("多模型智能助理"))
                                        .font(pf(12.5))
                                        .foregroundColor(C.subLabel)
                                }
                                Spacer(minLength: 0)
                            }

                            Text(Tr("问答、创作、联网检索与图片理解。购买 Token 后即可使用完整能力，额度实时到账。"))
                                .font(pf(13))
                                .lineSpacing(3)
                                .foregroundColor(C.subLabel)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack {
                                Spacer()
                                Text(Tr("进入小星 AI"))
                                    .font(pf(13, .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 18)
                                    .frame(height: 36)
                                    .background(Capsule().fill(Color(hex: 0x2F6FED)))
                            }
                        }
                        .padding(17)
                        .background(
                            LinearGradient(colors: [
                                Color.dyn(0xF2F6FF, 0x182338),
                                Color.dyn(0xEEF3FF, 0x142033)
                            ], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(hex: 0x2F6FED).opacity(0.10), lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)

                    GroupCard {
                        switchRow(icon: "eye", tint: C.green,
                                  title: Tr("小星"),
                                  sub: eyes.eyesOn
                                       ? Tr("正在用：") + eyesValue + Tr("　会话页顶栏那双眼睛")
                                       : Tr("已关闭：会话页顶栏那儿空出来，放大镜顶上去"),
                                  isOn: eyes.eyesOn) { on in
                            if on {

                                showFaceForEyes = true
                            } else {
                                Task { if let err = await eyes.set("off") { app.show(err) } }
                            }
                        } onOpen: { showEyes = true }
                        HairLine(inset: 16)
                        row(icon: "safari", tint: C.link,
                            title: Tr("内置浏览器"),
                            sub: Tr("在星言里直接打开网页，支持搜索、前进后退和分享"),
                            value: "") { showBrowser = true }
                        HairLine(inset: 16)
                        row(icon: "dot.radiowaves.left.and.right", tint: C.green,
                            title: Tr("文件快传"),
                            sub: Tr("两台手机面对面传照片、视频和文件，不经过聊天服务器"),
                            value: "") { showDrop = true }
                    }
                    .padding(.horizontal, 12)

                    Text(Tr("小星的开关在这一页里；浏览器和文件快传也放在这里。"))
                        .font(pf(12)).foregroundColor(C.subLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                    Spacer().frame(height: 10)
                }
                .padding(.vertical, 10)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task { await eyes.refresh() }

        .sheet(isPresented: $showFaceForEyes) {
            FaceVerifyFlowView { ok in
                showFaceForEyes = false
                if ok {
                    Task {

                        if let err = await eyes.set("on") { app.show(err) }
                        else { app.show(Tr("人脸验证通过，小星已打开")) }
                    }
                } else {
                    app.show(Tr("人脸验证没通过，小星先保持关闭"))
                }
            }
            .environmentObject(app)
        }
        .navigationDestination(isPresented: $showEyes) { EyesSettingsView() }
        .navigationDestination(isPresented: $showBrowser) { InAppBrowserView() }
        .navigationDestination(isPresented: $showAI) {
            AIPageView().environmentObject(app)
        }
        .fullScreenCover(isPresented: $showDrop) {
            FaceToFaceFileSheet(rows: [],
                                avatar: app.me?.avatarPath ?? "",
                                name: app.me?.name ?? "我",
                                ink: C.label,
                                mode: .host)
                .environmentObject(app)
        }
    }

    private func switchRow(icon: String, tint: Color, title: String, sub: String,
                           isOn: Bool, onSet: @escaping (Bool) -> Void,
                           onOpen: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 17))
                        .foregroundColor(tint)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(pf(16)).foregroundColor(C.label)
                        Text(sub).font(pf(12.5)).foregroundColor(C.subLabel)
                            .lineLimit(2).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle("", isOn: Binding(get: { isOn }, set: { onSet($0) }))
                .labelsHidden()
                .tint(C.green)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 66)
    }

    private func row(icon: String, tint: Color, title: String, sub: String,
                     value: String, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(tint)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(pf(15.5)).foregroundColor(C.label)
                    Text(sub).font(pf(12)).foregroundColor(C.subLabel).lineLimit(1)
                }
                Spacer(minLength: 8)
                if !value.isEmpty {
                    Text(value).font(pf(13)).foregroundColor(C.subLabel)
                }
                Chevron(size: 9, line: 1.5)
            }
            .padding(.horizontal, 16)
            .frame(height: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
