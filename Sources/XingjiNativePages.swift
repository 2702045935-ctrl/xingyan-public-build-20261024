import SwiftUI
import UIKit

enum XingjiNativePages {
    static let enabledKey = "chris.xingjiNativePages"
    static let legacyMainKey = "chris.legacyMainPages"
}

private enum XJN {
    static let jade = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: 0x67D6B0) : UIColor(hex: 0x176A57)
    })

    static let jadeSoft = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(hex: 0x18382F)
            : UIColor(hex: 0xDDEFE8)
    })

    static let gold = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: 0xE2B35F) : UIColor(hex: 0xC58C32)
    })

    static let canvas = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor.black : UIColor(hex: 0xF3F1EC)
    })

    static let surface = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: 0x101315) : UIColor(hex: 0xFCFBF8)
    })

    static let raised = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: 0x161A1D) : UIColor.white
    })

    static let divider = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.10)
            : UIColor(hex: 0xE5E1D9)
    })

    static let secondary = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: 0xA7B1AC) : UIColor(hex: 0x58635D)
    })

    static let tertiary = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: 0x737F79) : UIColor(hex: 0x89928D)
    })

    static let field = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.07)
            : UIColor(hex: 0xE9E6DF)
    })
}

struct XingjiNativePageHost: View {
    @Binding var tab: Int

    var body: some View {
        switch tab {
        case 0: XingjiNativeChatsPage()
        case 1: XingjiNativeContactsPage()
        case 2: XingjiNativeWorldPage()
        default: XingjiNativeMePage()
        }
    }
}

private struct XJHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let leading: AnyView?
    let trailing: Trailing

    init(title: String,
         subtitle: String? = nil,
         leading: AnyView? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            if let leading {
                leading
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(pf(21, .bold))
                    .foregroundColor(C.label)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(pf(10.5))
                        .foregroundColor(XJN.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(minHeight: 56)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(XJN.divider).frame(height: 0.5)
        }
    }
}

private struct XJSearchBar: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(XJN.tertiary)
            TextField(placeholder, text: $text)
                .font(pf(13.5))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(XJN.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 37)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(XJN.field))
    }
}

private struct XJRoundButton: View {
    let symbol: String
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(C.label)
                .frame(width: 36, height: 36)
                .background(Circle().fill(XJN.field))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct XJBadge: View {
    let count: Int
    var muted = false

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(pf(9.5, .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, count > 9 ? 5 : 4)
                .frame(minWidth: 19, minHeight: 19)
                .background(Capsule().fill(muted ? XJN.tertiary : XJN.jade))
        }
    }
}

private struct XJContactSection: Identifiable {
    let id: String
    let users: [User]
}

struct XingjiNativeChatsPage: View {
    @EnvironmentObject private var app: AppState
    @State private var query = ""
    @State private var filter = 0
    @State private var showAccounts = false
    @State private var showNewFriends = false
    @State private var showGroupCreate = false
    @State private var showScanner = false
    @State private var deleteTarget: Chat?

    private let filters = ["全部", "未读", "群聊", "公众号", "置顶"]

    private var chats: [Chat] {
        var result = app.chats.filter { chat in
            let title = (chat.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !chat.id.isEmpty else { return false }
            return !title.isEmpty || chat.lastMessage != nil || !(chat.avatar ?? "").isEmpty
        }
        switch filter {
        case 1: result = result.filter { $0.unreadCount > 0 || $0.flagged == true }
        case 2: result = result.filter { $0.type == "group" || ($0.memberCount ?? 0) > 2 }
        case 3: result = result.filter { !($0.oaId ?? "").isEmpty || $0.oaDigest == true }
        case 4: result = result.filter { $0.pinned == true }
        default: break
        }
        if !query.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || ($0.lastMessage?.preview ?? "").localizedCaseInsensitiveContains(query)
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            XJHeader(
                title: C.tabText0,
                subtitle: app.offline ? Tr("未连接") : "\(app.chats.reduce(0) { $0 + $1.unreadCount }) 条未读消息",
                leading: AnyView(
                    Button {
                        showAccounts = true
                    } label: {
                        Avatar(path: app.me?.avatarPath ?? "", size: 34, radius: 11)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Tr("切换账号"))
                )
            ) {
                HStack(spacing: 6) {
                    XJRoundButton(symbol: "qrcode.viewfinder", label: Tr("扫一扫")) {
                        showScanner = true
                    }
                    XJRoundButton(symbol: "plus", label: Tr("新建")) {
                        showGroupCreate = true
                    }
                }
            }

            VStack(spacing: 8) {
                XJSearchBar(text: $query, placeholder: Tr("搜索消息、联系人与功能"))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(filters.indices, id: \.self) { index in
                            Button {
                                withAnimation(.easeOut(duration: 0.16)) { filter = index }
                            } label: {
                                Text(Tr(filters[index]))
                                    .font(pf(12, filter == index ? .semibold : .regular))
                                    .foregroundColor(filter == index
                                        ? (UIColor.darkMode ? Color(hex: 0x07120E) : Color.white)
                                        : XJN.secondary)
                                    .padding(.horizontal, 12)
                                    .frame(height: 29)
                                    .background(
                                        Capsule().fill(filter == index ? XJN.jade : XJN.field)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            if app.loadingChats && app.chats.isEmpty {
                Spacer()
                ProgressView().tint(XJN.jade)
                Text(Tr("正在加载会话…"))
                    .font(pf(12))
                    .foregroundColor(XJN.secondary)
                    .padding(.top, 8)
                Spacer()
            } else if chats.isEmpty {
                Spacer()
                VStack(spacing: 9) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 30, weight: .light))
                        .foregroundColor(XJN.tertiary)
                    Text(query.isEmpty ? Tr("暂无会话") : Tr("没有找到相关会话"))
                        .font(pf(14))
                        .foregroundColor(XJN.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(chats) { chat in
                            Button {
                                app.openChat = chat
                            } label: {
                                XJChatRow(chat: chat)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    Task {
                                        _ = await API.shared.setPinned(chatId: chat.id, pinned: !(chat.pinned == true))
                                        await app.loadChats()
                                    }
                                } label: {
                                    Label(chat.pinned == true ? Tr("取消置顶") : Tr("置顶聊天"),
                                          systemImage: "pin")
                                }
                                Button {
                                    Task {
                                        _ = await API.shared.setMuted(chatId: chat.id, muted: !(chat.muted == true))
                                        await app.loadChats()
                                    }
                                } label: {
                                    Label(chat.muted == true ? Tr("取消免打扰") : Tr("消息免打扰"),
                                          systemImage: "bell.slash")
                                }
                                Button {
                                    Task {
                                        await API.shared.markUnread(chatId: chat.id)
                                        await app.loadChats()
                                    }
                                } label: {
                                    Label(Tr("标为未读"), systemImage: "envelope.badge")
                                }
                                Button(role: .destructive) {
                                    deleteTarget = chat
                                } label: {
                                    Label(Tr("删除会话"), systemImage: "trash")
                                }
                            }
                            Divider().overlay(XJN.divider).padding(.leading, 72)
                        }
                        Spacer().frame(height: 82)
                    }
                }
                .refreshable { await app.loadChats() }
            }
        }
        .background(XJN.canvas.ignoresSafeArea())
        .sheet(isPresented: $showAccounts) {
            NavigationStack { SwitchAccountView().environmentObject(app) }
        }
        .sheet(isPresented: $showNewFriends) {
            NavigationStack { NewFriendsView().environmentObject(app) }
        }
        .sheet(isPresented: $showGroupCreate) {
            NavigationStack {
                GroupCreateView { chat in
                    app.openChat = chat
                }
                .environmentObject(app)
            }
        }
        .sheet(isPresented: $showScanner) {
            ScannerView { text in
                if !text.isEmpty { app.show(text) }
            }
        }
        .confirmationDialog(Tr("删除这个会话？"), isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        ), titleVisibility: .visible) {
            Button(Tr("删除"), role: .destructive) {
                guard let chat = deleteTarget else { return }
                deleteTarget = nil
                Task {
                    _ = await API.shared.hideChat(chatId: chat.id)
                    await app.loadChats()
                }
            }
            Button(Tr("取消"), role: .cancel) { deleteTarget = nil }
        }
    }
}

private struct XJChatRow: View {
    let chat: Chat

    var body: some View {
        HStack(spacing: 11) {
            Avatar(path: chat.avatar ?? "", size: 48, radius: 13,
                   level: chat.qqLevel ?? 0)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(chat.name)
                        .font(pf(15.5, .semibold))
                        .foregroundColor(C.label)
                        .lineLimit(1)
                    if chat.pinned == true {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9.5))
                            .foregroundColor(XJN.tertiary)
                    }
                    Spacer(minLength: 4)
                    if chat.muted == true {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 9.5))
                            .foregroundColor(XJN.tertiary)
                    }
                    Text(TimeFmt.list(chat.lastMessage?.createdAt ?? chat.updatedAt))
                        .font(pf(10.5))
                        .foregroundColor(XJN.tertiary)
                }
                HStack(spacing: 8) {
                    Text(chat.lastMessage?.preview ?? "")
                        .font(pf(13))
                        .foregroundColor(XJN.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    XJBadge(count: chat.unreadCount, muted: chat.muted == true)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

struct XingjiNativeContactsPage: View {
    @EnvironmentObject private var app: AppState
    @State private var query = ""
    @State private var showNewFriends = false

    private var contacts: [User] {
        app.contacts
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
                || ($0.username ?? "").localizedCaseInsensitiveContains(query) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var groups: [XJContactSection] {
        let grouped = Dictionary(grouping: contacts) { user -> String in
            guard let first = user.name.first else { return "#" }
            let s = String(first).uppercased()
            return s.range(of: "[A-Z]", options: .regularExpression) == nil ? "#" : s
        }
        return grouped.keys.sorted().map {
            XJContactSection(id: $0, users: grouped[$0] ?? [])
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                XJHeader(
                    title: C.tabText1,
                    subtitle: "\(app.contacts.count) 位朋友" + (app.friendRequests > 0 ? " · \(app.friendRequests) 个新朋友" : "")
                ) {
                    XJRoundButton(symbol: "person.badge.plus", label: Tr("添加朋友")) {
                        showNewFriends = true
                    }
                }
                VStack(spacing: 9) {
                    XJSearchBar(text: $query, placeholder: Tr("搜索联系人"))
                    HStack(spacing: 8) {
                        contactShortcut(title: Tr("新的朋友"), icon: "person.badge.plus",
                                        badge: app.friendRequests) {
                            NewFriendsView().environmentObject(app)
                        }
                        contactShortcut(title: Tr("群聊"), icon: "person.2", badge: 0) {
                            GroupListView { chat in
                                app.openChat = chat
                            }
                            .environmentObject(app)
                        }
                        contactShortcut(title: Tr("星标"), icon: "star", badge: 0) {
                            XingjiStarFriendsView()
                                .environmentObject(app)
                        }
                        contactShortcut(title: Tr("二维码"), icon: "qrcode", badge: 0) {
                            MyQRView().environmentObject(app)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groups) { section in
                            Text(section.id)
                                .font(pf(11, .semibold))
                                .foregroundColor(XJN.tertiary)
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                                .padding(.bottom, 5)
                            VStack(spacing: 0) {
                                ForEach(section.users) { user in
                                    NavigationLink {
                                        ContactCardView(
                                            user: user,
                                            onOpenChat: { chat in app.openChat = chat },
                                            onOpenMoments: { _ in }
                                        )
                                        .environmentObject(app)
                                    } label: {
                                        HStack(spacing: 11) {
                                            Avatar(path: user.avatarPath, size: 40, radius: 11,
                                                   level: user.qqLevel ?? 0)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(user.groupName)
                                                    .font(pf(14.5, .medium))
                                                    .foregroundColor(C.label)
                                                    .lineLimit(1)
                                                Text(user.status?.isEmpty == false ? user.status! : "@" + (user.username ?? ""))
                                                    .font(pf(10.5))
                                                    .foregroundColor(XJN.secondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer(minLength: 0)
                                            if user.star == true {
                                                Image(systemName: "star.fill")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(XJN.gold)
                                            }
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(XJN.tertiary)
                                        }
                                        .padding(.horizontal, 13)
                                        .frame(height: 60)
                                        .background(XJN.surface)
                                    }
                                    .buttonStyle(.plain)
                                    if user.id != section.users.last?.id {
                                        Divider().overlay(XJN.divider).padding(.leading, 64)
                                    }
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(XJN.divider, lineWidth: 0.5))
                            .padding(.horizontal, 12)
                        }
                        Spacer().frame(height: 82)
                    }
                }
                .refreshable { await app.loadContacts() }
            }
            .background(XJN.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showNewFriends) {
                NavigationStack { NewFriendsView().environmentObject(app) }
            }
        }
    }

    private func contactShortcut<Destination: View>(
        title: String, icon: String, badge: Int,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundColor(XJN.jade)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(XJN.jadeSoft))
                    if badge > 0 {
                        XJBadge(count: badge).offset(x: 3, y: -3)
                    }
                }
                Text(title)
                    .font(pf(9.5))
                    .foregroundColor(XJN.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

struct XingjiNativeWorldPage: View {
    @EnvironmentObject private var app: AppState

    private var recentMoments: [Moment] {
        Array(app.moments.prefix(4))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                XJHeader(title: C.tabText2, subtitle: Tr("记录此刻，也连接远方")) {
                    XJRoundButton(symbol: "magnifyingglass", label: Tr("搜索")) {}
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 13) {
                        if !recentMoments.isEmpty {
                            Text(Tr("此刻"))
                                .font(pf(14, .semibold))
                                .foregroundColor(C.label)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(recentMoments) { moment in
                                        VStack(spacing: 5) {
                                            Avatar(path: moment.author?.avatarPath ?? "",
                                                   size: 52, radius: 0, circle: true)
                                                .padding(3)
                                                .overlay(Circle().stroke(XJN.jade, lineWidth: 2))
                                            Text(moment.author?.groupName ?? Tr("朋友"))
                                                .font(pf(9.5))
                                                .foregroundColor(XJN.secondary)
                                                .lineLimit(1)
                                                .frame(width: 64)
                                        }
                                    }
                                }
                            }
                        }

                        NavigationLink {
                            MomentsView().environmentObject(app)
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(LinearGradient(
                                        colors: [Color(hex: 0x172A25), Color(hex: 0x0F201B)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                Image(systemName: "network")
                                    .font(.system(size: 90, weight: .ultraLight))
                                    .foregroundColor(.white.opacity(0.09))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .padding(.trailing, 18)
                                VStack(alignment: .leading, spacing: 9) {
                                    Text("星联世界")
                                        .font(pf(10, .semibold))
                                        .foregroundColor(XJN.gold)
                                        .tracking(1.2)
                                    Text(Tr("把沟通延伸到更大的现场"))
                                        .font(pf(24, .semibold))
                                        .foregroundColor(.white)
                                        .lineLimit(2)
                                    Text(Tr("生活圈 · 公共内容 · 小程序"))
                                        .font(pf(10.5))
                                        .foregroundColor(.white.opacity(0.62))
                                }
                                .padding(18)
                            }
                            .frame(height: 172)
                        }
                        .buttonStyle(.plain)

                        VStack(spacing: 0) {
                            worldLink(Tr("生活圈"), sub: Tr("朋友的新鲜动态"),
                                      icon: "photo.on.rectangle.angled") {
                                MomentsView().environmentObject(app)
                            }
                            Divider().overlay(XJN.divider).padding(.leading, 55)
                            worldLink(Tr("公众号"), sub: Tr("内容与服务"),
                                      icon: "megaphone") {
                                OfficialAccountsView().environmentObject(app)
                            }
                            Divider().overlay(XJN.divider).padding(.leading, 55)
                            worldLink(Tr("小程序"), sub: Tr("最近使用与能力"),
                                      icon: "square.grid.2x2") {
                                MiniAppsView().environmentObject(app)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(XJN.divider, lineWidth: 0.5))
                        Spacer().frame(height: 82)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                }
            }
            .background(XJN.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func worldLink<Destination: View>(
        _ title: String, sub: String, icon: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(XJN.jade)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(XJN.jadeSoft))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(pf(14.5, .medium)).foregroundColor(C.label)
                    Text(sub).font(pf(10.5)).foregroundColor(XJN.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(XJN.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 58)
            .background(XJN.surface)
        }
        .buttonStyle(.plain)
    }
}

private struct XingjiStarFriendsView: View {
    @EnvironmentObject private var app: AppState
    @State private var ids: [String] = []

    private var users: [User] {
        app.contacts.filter { ids.contains($0.id) }
    }

    var body: some View {
        List {
            if users.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "star")
                        .font(.system(size: 30, weight: .light))
                        .foregroundColor(XJN.tertiary)
                    Text(Tr("还没有星标朋友"))
                        .font(pf(14))
                        .foregroundColor(XJN.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(users) { user in
                        NavigationLink {
                            ContactCardView(
                                user: user,
                                onOpenChat: { chat in app.openChat = chat },
                                onOpenMoments: { _ in }
                            )
                            .environmentObject(app)
                        } label: {
                            HStack(spacing: 11) {
                                Avatar(path: user.avatarPath, size: 40, radius: 11,
                                       level: user.qqLevel ?? 0)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.groupName)
                                        .font(pf(14.5, .medium))
                                        .foregroundColor(C.label)
                                    Text("@" + (user.username ?? ""))
                                        .font(pf(10.5))
                                        .foregroundColor(XJN.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(XJN.canvas)
        .navigationTitle(Tr("星标朋友"))
        .toolbar(.visible, for: .navigationBar)
        .task {
            ids = (try? await API.shared.starredFriends()) ?? []
        }
    }
}

struct XingjiNativeMePage: View {
    @EnvironmentObject private var app: AppState
    @State private var showAccounts = false
    @State private var showQR = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                XJHeader(title: C.tabText3, subtitle: Tr("我的星言")) {
                    XJRoundButton(symbol: "qrcode", label: Tr("二维码")) {
                        showQR = true
                    }
                }
                ScrollView {
                    VStack(spacing: 12) {
                        profileCard
                        statsCard
                        VStack(spacing: 0) {
                            meLink(Tr("小星 AI"), sub: Tr("整理消息与日程"),
                                   icon: "sparkles") {
                                AIPageView().environmentObject(app)
                            }
                            Divider().overlay(XJN.divider).padding(.leading, 55)
                            meLink(Tr("收藏与备忘"), sub: Tr("图片、文件和笔记"),
                                   icon: "bookmark") {
                                FavoritesView().environmentObject(app)
                            }
                            Divider().overlay(XJN.divider).padding(.leading, 55)
                            meLink(Tr("钱包"), sub: Tr("余额、账单和支付设置"),
                                   icon: "wallet.pass") {
                                WalletView().environmentObject(app)
                            }
                            Divider().overlay(XJN.divider).padding(.leading, 55)
                            meLink(Tr("设置"), sub: Tr("账号、通用与功能"),
                                   icon: "gearshape") {
                                SettingsView().environmentObject(app)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(XJN.divider, lineWidth: 0.5))
                        Spacer().frame(height: 82)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                }
            }
            .background(XJN.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showAccounts) {
            NavigationStack { SwitchAccountView().environmentObject(app) }
        }
        .sheet(isPresented: $showQR) {
            NavigationStack { MyQRView().environmentObject(app) }
        }
    }

    private var profileCard: some View {
        Button {
            showAccounts = true
        } label: {
            HStack(spacing: 12) {
                Avatar(path: app.me?.avatarPath ?? "", size: 58, radius: 17,
                       level: app.me?.qqLevel ?? 0)
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.me?.groupName ?? Tr("星言用户"))
                        .font(pf(19, .semibold))
                        .foregroundColor(C.label)
                        .lineLimit(1)
                    Text("@" + (app.me?.username ?? "-"))
                        .font(pf(10.5))
                        .foregroundColor(XJN.secondary)
                    Text(app.me?.moodText?.isEmpty == false ? app.me!.moodText! : Tr("记录此刻，也连接远方"))
                        .font(pf(10.5))
                        .foregroundColor(XJN.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(XJN.tertiary)
            }
            .padding(15)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(XJN.surface))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(XJN.divider, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Tr("切换账号"))
    }

    private var statsCard: some View {
        HStack(spacing: 0) {
            stat("\(app.contacts.count)", Tr("朋友"))
            Divider().frame(height: 31).overlay(XJN.divider)
            stat("Lv.\(app.me?.qqLevel ?? 1)", Tr("等级"))
            Divider().frame(height: 31).overlay(XJN.divider)
            stat("\(app.me?.momentCount ?? 0)", Tr("动态"))
        }
        .padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(XJN.surface))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
            .stroke(XJN.divider, lineWidth: 0.5))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(pf(16, .semibold)).foregroundColor(C.label)
            Text(label).font(pf(9)).foregroundColor(XJN.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func meLink<Destination: View>(
        _ title: String, sub: String, icon: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(XJN.jade)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(XJN.jadeSoft))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(pf(14.5, .medium)).foregroundColor(C.label)
                    Text(sub).font(pf(10.5)).foregroundColor(XJN.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(XJN.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 58)
            .background(XJN.surface)
        }
        .buttonStyle(.plain)
    }
}

private extension UIColor {
    static var darkMode: Bool {
        UITraitCollection.current.userInterfaceStyle == .dark
    }
}
