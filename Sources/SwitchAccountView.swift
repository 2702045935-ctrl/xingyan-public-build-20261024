import SwiftUI

struct SwitchAccountView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var growth = GrowthStore.shared

    @State private var adding = false
    @State private var busy = ""
    @State private var note = ""

    private var me: String { app.me?.username ?? "" }

    var body: some View {
        VStack(spacing: 0) {

            HStack(spacing: 0) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundColor(C.label)
                        .frame(height: L.navH)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Text(Tr("切换账号")).font(pf(17, .semibold)).foregroundColor(C.label)
                Spacer(minLength: 0)
                Color.clear.frame(width: 51, height: L.navH)
            }
            .frame(height: L.navH)
            .background(C.navBg)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    Text(Tr("轻触头像以切换账号"))
                        .font(pf(16.5))
                        .foregroundColor(C.label)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 56)
                        .padding(.bottom, 40)

                    VStack(spacing: 12) {
                        ForEach(app.accounts) { acct in
                            accountRow(acct)
                        }
                        addRow
                    }
                    .padding(.horizontal, 24)

                    if !note.isEmpty {
                        Text(note)
                            .font(pf(13))
                            .foregroundColor(Color(hexString: "#FA5151"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 22)
                            .padding(.top, 10)
                    }

                    Spacer().frame(height: 30)
                }
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .fullScreenCover(isPresented: $adding) {
            HarmonyLoginView()
                .environmentObject(app)
        }
    }

    @ViewBuilder
    private func accountRow(_ a: SavedAccount) -> some View {
        let current = (a.username == me)
        Button {
            tap(a, current: current)
        } label: {

            HStack(spacing: 12) {
                Avatar(path: a.avatar, size: 48, radius: 7, level: levelOf(a))
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(a.nickname.isEmpty ? a.username : a.nickname)
                        .font(pf(17))
                        .foregroundColor(C.label)
                        .lineLimit(1)
                    Text(a.username)
                        .font(pf(13))
                        .foregroundColor(C.subLabel)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if busy == a.username {
                    ProgressView()
                } else if current {
                    Text(Tr("当前使用"))
                        .font(pf(13.5))
                        .foregroundColor(C.subLabel)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 80)
            .background(C.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !current {
                Button(role: .destructive) { remove(a) } label: {
                    Label(Tr("从这台设备移除"), systemImage: "trash")
                }
            }
        }
    }

    private var addRow: some View {
        Button { adding = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.dyn(0xEDEDED, 0x2C2C2E))
                        .frame(width: 48, height: 48)
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(C.subLabel)
                }
                Text(Tr("添加账号"))
                    .font(pf(17))
                    .foregroundColor(C.label)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 80)
            .background(C.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func levelOf(_ a: SavedAccount) -> Int {
        if a.username == me { return max(1, growth.shownLevel) }
        if let lv = app.contacts.first(where: { $0.username == a.username })?.qqLevel, lv > 0 { return lv }
        return 0
    }

    private func tap(_ a: SavedAccount, current: Bool) {
        guard !current, busy.isEmpty else { return }
        switchTo(a)
    }

    private func switchTo(_ a: SavedAccount) {
        note = ""
        busy = a.username
        Task {
            let saved = AccountStore.token(for: a.username)
            guard !saved.isEmpty else {
                busy = ""
                note = Tr("这个账号的登录状态过期了，重新输一次密码就行")
                adding = true
                return
            }
            let ok = await app.quickLogin(token: saved,
                                          username: a.username,
                                          switchingAccount: true)
            busy = ""
            if ok {
                dismiss()
            } else {
                note = Tr("这个账号的登录状态过期了，重新输一次密码就行")
                adding = true
            }
        }
    }

    private func remove(_ a: SavedAccount) {
        AccountStore.remove(username: a.username)
        app.accounts = AccountStore.load()
        app.show(Tr("已移除") + "「" + a.nickname + "」")
    }
}
