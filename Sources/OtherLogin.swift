import SwiftUI

@MainActor
final class OtherLogin: ObservableObject {
    static let shared = OtherLogin()

    @Published var open = false

    @Published var device = ""

    @Published var at = Date()

    private var locked = false

    func trigger(device: String, atMillis: Double = 0) {
        guard !locked else { return }
        if !device.isEmpty { self.device = device }
        if atMillis > 0 { self.at = Date(timeIntervalSince1970: atMillis / 1000) }
        else { self.at = Date() }
        open = true

        Realtime.shared.stop()
        AppLog.error("被顶下线", "账号在「" + (self.device.isEmpty ? "另一台设备" : self.device) + "」上登录")
    }

    func dismiss() {
        locked = true
        open = false
    }

    func reset() {
        locked = false
        open = false
        device = ""
    }

    var detailText: String {
        let df = DateFormatter()
        df.dateFormat = "MM-dd HH:mm"
        let d = device.isEmpty ? "另一台\(AppInfo.deviceKindName)" : device
        return "登录设备：" + d + "\n登录时间：" + df.string(from: at)
    }
}

struct OtherLoginCard: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var kick = OtherLogin.shared

    var body: some View {
        Group {
            if kick.open {
                ZStack {
                    Color.black.opacity(0.28).ignoresSafeArea()
                    VStack(spacing: 0) {
                        Text(Tr("你的账号在另一台设备上登录"))
                            .font(pf(17, .semibold))
                            .foregroundColor(C.label)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 22)
                            .padding(.top, 26)

                        Text(kick.detailText)
                            .font(pf(13.5))
                            .foregroundColor(C.subLabel)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 22)
                            .padding(.top, 10)

                        Text(Tr("如果不是你本人操作，请立刻修改密码。"))
                            .font(pf(13))
                            .foregroundColor(C.subLabel)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 22)
                            .padding(.top, 8)

                        Rectangle().fill(C.hairline).frame(height: 0.5).padding(.top, 20)

                        HStack(spacing: 0) {
                            Button {
                                kick.dismiss()
                            } label: {
                                Text(Tr("我知道了"))
                                    .font(pf(16))
                                    .foregroundColor(C.label)
                                    .frame(maxWidth: .infinity).frame(height: 50)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Rectangle().fill(C.hairline).frame(width: 0.5, height: 50)

                            Button {
                                kick.reset()
                                Task { await app.logout() }
                            } label: {
                                Text(Tr("退出"))
                                    .font(pf(16, .medium))
                                    .foregroundColor(C.red)
                                    .frame(maxWidth: .infinity).frame(height: 50)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: 280)
                    .background(C.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.22), radius: 22, y: 8)
                }
            }
        }
    }
}
