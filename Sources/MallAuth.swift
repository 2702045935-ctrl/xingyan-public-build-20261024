import SwiftUI

@MainActor
final class MallAuthStore: ObservableObject {
    static let shared = MallAuthStore()

    @Published private(set) var grantedTo: String = ""

    @Published private(set) var grantedAt: Double = 0

    private let kUser = "dd.mallAuth.user"
    private let kAt = "dd.mallAuth.at"

    private init() {
        grantedTo = UserDefaults.standard.string(forKey: kUser) ?? ""
        grantedAt = UserDefaults.standard.double(forKey: kAt)
    }

    func isGranted(_ uid: String) -> Bool { !uid.isEmpty && grantedTo == uid }

    func grant(_ uid: String) {
        guard !uid.isEmpty else { return }
        grantedTo = uid
        grantedAt = Date().timeIntervalSince1970 * 1000
        UserDefaults.standard.set(uid, forKey: kUser)
        UserDefaults.standard.set(grantedAt, forKey: kAt)
    }

    func revoke() {
        grantedTo = ""
        grantedAt = 0
        UserDefaults.standard.removeObject(forKey: kUser)
        UserDefaults.standard.removeObject(forKey: kAt)
    }
}

struct MallAuthCard: View {

    var appName: String

    var myAvatar: String = ""
    var myName: String = ""
    var myId: String = ""
    var onAllow: () -> Void
    var onDeny: () -> Void

    var body: some View {
        ZStack {

            Color.black.opacity(0.35).ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 9) {

                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(DDColor.gradBtn)
                        .frame(width: 56, height: 56)
                        .overlay(Image(systemName: "bag.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(.white))
                    Text(appName.isEmpty ? Tr("商城") : appName)
                        .font(pf(17, .semibold)).foregroundColor(C.label)
                    Text(Tr("申请获取以下权限"))
                        .font(pf(13)).foregroundColor(C.subLabel)
                }
                .padding(.top, 24)
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 5) {
                    Text(Tr("获取你的公开信息"))
                        .font(pf(15)).foregroundColor(C.label)

                    HStack(spacing: 10) {
                        Avatar(path: myAvatar, size: 40, circle: true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(myName.isEmpty ? Tr("（还没有昵称）") : myName)
                                .font(pf(14.5, .medium)).foregroundColor(C.label).lineLimit(1)
                            Text(myId.isEmpty ? Tr("昵称、头像、星言号")
                                              : (Tr("星言号 ") + myId))
                                .font(pf(12)).foregroundColor(C.subLabel).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(C.green)
                    }
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 10).fill(C.pageBg))
                .padding(.horizontal, 22)
                .padding(.top, 16)

                Text(Tr("同意后，商城里会用你的头像和昵称显示身份；随时可以在 设置 → 个人信息与权限 → 授权管理 里解除。"))
                    .font(pf(11.5)).foregroundColor(C.subLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.top, 10)

                HairLine().padding(.top, 18)
                HStack(spacing: 0) {
                    Button(action: onDeny) {
                        Text(Tr("拒绝"))
                            .font(pf(16.5)).foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(C.hairline).frame(width: 0.5, height: 50)
                    Button(action: onAllow) {

                        Text(Tr("允许"))
                            .font(pf(16.5, .medium)).foregroundColor(C.green)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 300)
            .background(C.meCardBg)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

struct MallAuthGate<Content: View>: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = MallAuthStore.shared
    @ObservedObject private var store = DDStore.shared

    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    private var uid: String { app.me?.id ?? "" }

    var body: some View {
        ZStack {

            if uid.isEmpty || auth.isGranted(uid) {
                content()
            } else {
                C.pageBg.ignoresSafeArea()
                MallAuthCard(appName: store.mallName,
                             myAvatar: app.me?.avatarPath ?? "",
                             myName: app.me?.nickname ?? "",
                             myId: app.me?.username ?? "",
                             onAllow: { auth.grant(uid) },
                             onDeny: {
                                 app.show(Tr("已拒绝授权，暂时进不了商城"))
                                 dismiss()
                             })
            }
        }

        .task { if store.mallName.isEmpty { await store.refresh() } }
    }
}
