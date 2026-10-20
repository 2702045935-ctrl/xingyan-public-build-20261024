import SwiftUI

/* ============================================================
   推荐给朋友（微信那张「发送给」页）—— 桌面 安全 文件夹截图 1 的样子：
     · 顶栏：「发送给」+ 右上「取消」
     · 一个搜索框
     · 「最近聊天」+「联系人」：都可搜索、可多选
     · 没有历史会话的好友也能直接创建单聊并发送
     · 底部固定一张**个人名片**预览和绿色「发送」，不用滚到底
   发出去的是名片消息（kind = card），收端按微信那张卡渲染。
   ⚠ 名字 / 微信号都要先解码再显示（收端乱码就是漏了这一步）。
   ============================================================ */
struct CardShareView: View {
    /// 要推荐出去的那个人
    let user: User
    /// 发送完成（调用方可以顺手刷新会话列表）
    var onSent: () -> Void = {}

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var picked: Set<String> = []
    @State private var sending = false

    private var recentRows: [Chat] {
        let list = app.chats.filter { c in
            if (c.type ?? "direct") == "group" { return true }
            return c.memberIds?.contains(user.id) != true
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    /// 最近聊天里已经出现的人不重复放进通讯录分组。
    private var contactRows: [User] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let recentUserIds = Set(recentRows.compactMap { chat -> String? in
            guard (chat.type ?? "direct") != "group" else { return nil }
            return chat.memberIds?.first(where: { $0 != app.me?.id })
        })
        return app.contacts.filter { u in
            guard u.id != user.id, u.bot != true, !recentUserIds.contains(u.id) else { return false }
            if q.isEmpty { return true }
            let name = u.name + " " + (u.username ?? "")
            return name.localizedCaseInsensitiveContains(q)
        }
    }

    private var pickedCount: Int { picked.count }

    private func pickKey(_ c: Chat) -> String { "chat:" + c.id }

    private func pickKey(_ u: User) -> String {
        if let c = app.chats.first(where: {
            ($0.type ?? "direct") != "group" && ($0.memberIds?.contains(u.id) == true)
        }) {
            return pickKey(c)
        }
        return "user:" + u.id
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("发送给"), back: { dismiss() }) {
                Button { dismiss() } label: {
                    Text(Tr("取消")).font(pf(17)).foregroundColor(C.label)
                        .frame(height: L.navH).padding(.trailing, 16)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(spacing: 0) {
                    searchBar
                    if !recentRows.isEmpty {
                        sectionTitle(Tr("最近聊天"))
                        GroupCard {
                            ForEach(Array(recentRows.prefix(30).enumerated()), id: \.offset) { i, c in
                                if i > 0 { HairLine(inset: 60) }
                                chatRow(c)
                            }
                        }
                    }
                    if !contactRows.isEmpty {
                        sectionTitle(Tr("联系人"))
                        GroupCard {
                            ForEach(Array(contactRows.prefix(80).enumerated()), id: \.offset) { i, u in
                                if i > 0 { HairLine(inset: 60) }
                                contactRow(u)
                            }
                        }
                    }
                    if recentRows.isEmpty && contactRows.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 24)).foregroundColor(C.subLabel)
                            Text(Tr("没有找到联系人")).font(pf(14)).foregroundColor(C.subLabel)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 56)
                    }
                    Spacer().frame(height: 12)
                }
            }
            .background(C.pageBg)
            bottomBar
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
    }

    /* ---------------------------------------------------------- 零件 */

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 14.5)).foregroundColor(C.searchIcon)
            TextField(Tr("搜索"), text: $query).font(pf(15))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15)).foregroundColor(C.searchIcon2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(C.searchBg))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(C.hairline, lineWidth: 0.6))
        .padding(.horizontal, 14).padding(.top, 10)
    }

    private func sectionTitle(_ text: String) -> some View {
        HStack {
            Text(text).font(pf(13)).foregroundColor(C.subLabel)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 6)
    }

    private func chatRow(_ c: Chat) -> some View {
        let key = pickKey(c)
        let on = picked.contains(key)
        return Button {
            if on { picked.remove(key) } else { picked.insert(key) }
        } label: {
            HStack(spacing: 12) {
                Avatar(path: c.avatar ?? "", size: 40, radius: c.type == "group" ? 8 : 20)
                Text(c.name).font(pf(16)).foregroundColor(C.label).lineLimit(1)
                Spacer(minLength: 8)
                if on {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 19)).foregroundColor(C.green)
                }
            }
            .padding(.horizontal, 16).frame(height: 60)
            .background(C.cardBg).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(sending)
    }

    private func contactRow(_ u: User) -> some View {
        let key = pickKey(u)
        let on = picked.contains(key)
        return Button {
            if on { picked.remove(key) } else { picked.insert(key) }
        } label: {
            HStack(spacing: 12) {
                Avatar(path: u.avatarPath, size: 40, radius: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(u.name).font(pf(16)).foregroundColor(C.label).lineLimit(1)
                    if let username = u.username, !username.isEmpty {
                        Text(username).font(pf(12.5)).foregroundColor(C.subLabel).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if on {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 19)).foregroundColor(C.green)
                }
            }
            .padding(.horizontal, 16).frame(height: 60)
            .background(C.cardBg).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(sending)
    }

    /// 名片预览卡：微信那张（头像 + 名字 + 微信号 + 下面「个人名片」底条）
    private var cardPreview: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Avatar(path: user.avatarPath, size: 48, radius: 4)
                VStack(alignment: .leading, spacing: 5) {
                    Text(decode(user.name)).font(pf(16)).foregroundColor(C.label).lineLimit(1)
                    Text(Tr("微信号") + "：" + decode(user.username ?? "—"))
                        .font(pf(13)).foregroundColor(C.subLabel).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 10)

            HairLine(inset: 12)

            HStack(spacing: 6) {
                Image(systemName: "person.crop.square")
                    .font(.system(size: 12)).foregroundColor(C.subLabel)
                Text(Tr("个人名片")).font(pf(12.5)).foregroundColor(C.subLabel)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).frame(height: 28)
        }
        .frame(width: 250)
        .background(C.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(C.hairline, lineWidth: 0.6))
    }

    /// 底部固定发送区：微信逻辑选完人直接发，不让用户再滚到页面最底下。
    private var bottomBar: some View {
        VStack(spacing: 10) {
            cardPreview
            HStack {
                Text(picked.isEmpty ? Tr("选择联系人") : Tr("已选择 \(pickedCount) 个"))
                    .font(pf(13)).foregroundColor(C.subLabel)
                Spacer(minLength: 0)
                Button {
                    sendPicked()
                } label: {
                    Group {
                        if sending {
                            ProgressView().tint(.white)
                        } else {
                            Text(Tr("发送") + (picked.isEmpty ? "" : "（\(pickedCount)）"))
                        }
                    }
                    .font(pf(15, .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18).frame(minWidth: 82, minHeight: 36)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(picked.isEmpty || sending ? C.green.opacity(0.5) : C.green))
                }
                .buttonStyle(.plain)
                .disabled(picked.isEmpty || sending)
            }
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, max(10, L.safeBottom))
        .background(C.pageBg)
        .overlay(alignment: .top) { HairLine(inset: 0) }
    }

    private func sendPicked() {
        let chatIds = picked.compactMap { key -> String? in
            key.hasPrefix("chat:") ? String(key.dropFirst(5)) : nil
        }
        let userIds = picked.compactMap { key -> String? in
            key.hasPrefix("user:") ? String(key.dropFirst(5)) : nil
        }
        guard !chatIds.isEmpty || !userIds.isEmpty else {
            app.show(Tr("先选一个聊天"))
            return
        }
        let payload = [
            "userId": user.id,
            "name": user.name,
            "username": user.username ?? "",
            "avatar": user.avatar ?? ""
        ]
        let content = (try? JSONSerialization.data(withJSONObject: payload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{\"userId\":\"\(user.id)\"}"

        sending = true
        Task { @MainActor in
            var sent = 0
            var failed = 0
            for chatId in chatIds {
                do {
                    _ = try await API.shared.send(chatId: chatId, kind: "card", content: content)
                    sent += 1
                } catch {
                    failed += 1
                }
            }
            for userId in userIds {
                do {
                    let chat = try await API.shared.directChat(userId: userId)
                    _ = try await API.shared.send(chatId: chat.id, kind: "card", content: content)
                    sent += 1
                } catch {
                    failed += 1
                }
            }
            sending = false
            guard sent > 0 else {
                app.show(Tr("名片没发出去"))
                return
            }
            onSent()
            dismiss()
            app.show(failed == 0 ? Tr("已发送") : Tr("已发送 \(sent) 个，\(failed) 个失败"))
        }
    }

    /// 显示前先解码（客户端存的可能是百分号编码 —— 不解码就是收端看到的乱码）
    private func decode(_ s: String) -> String {
        s.removingPercentEncoding ?? s
    }
}
