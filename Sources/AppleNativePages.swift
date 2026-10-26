import SwiftUI

private enum AN {
    static let accent = Color.dyn(0x176A57, 0x63C6A5)
    static let groupedBg = Color(uiColor: .systemGroupedBackground)
    static let rowBg = Color(uiColor: .secondarySystemGroupedBackground)
    static let field = Color(uiColor: .tertiarySystemFill)
}

struct AppleNativePageHost: View {
    @Binding var tab: Int

    var body: some View {
        switch tab {
        case 0: AppleChatsView()
        case 1: AppleContactsView()
        case 2: AppleWorldView()
        default: AppleMeView()
        }
    }
}

private struct AppleChatsView: View {
    @EnvironmentObject private var app: AppState
    @State private var query = ""
    @State private var filter = 0
    @State private var showAccounts = false
    @State private var showScanner = false
    @State private var showNewGroup = false
    @State private var deleteTarget: Chat?

    private let filters = ["全部", "未读", "群聊", "公众号", "置顶"]

    private var chats: [Chat] {
        var result = app.chats.filter { chat in
            let title = (chat.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !chat.id.isEmpty && (!title.isEmpty || chat.lastMessage != nil || !(chat.avatar ?? "").isEmpty)
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
        NavigationStack {
            Group {
                if app.loadingChats && app.chats.isEmpty {
                    ProgressView(Tr("正在加载会话…"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if chats.isEmpty {
                    emptyState
                } else {
                    chatList
                }
            }
            .background(AN.groupedBg.ignoresSafeArea())
            .navigationTitle(C.tabText0)
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Tr("搜索消息、联系人与功能"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showAccounts = true
                    } label: {
                        Avatar(path: app.me?.avatarPath ?? "", size: 30, radius: 15)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Tr("切换账号"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker(Tr("筛选会话"), selection: $filter) {
                            ForEach(filters.indices, id: \.self) { i in
                                Text(Tr(filters[i])).tag(i)
                            }
                        }
                        Divider()
                        Button {
                            showScanner = true
                        } label: {
                            Label(Tr("扫一扫"), systemImage: "qrcode.viewfinder")
                        }
                        Button {
                            showNewGroup = true
                        } label: {
                            Label(Tr("发起群聊"), systemImage: "person.2.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showAccounts) {
            NavigationStack { SwitchAccountView().environmentObject(app) }
        }
        .sheet(isPresented: $showNewGroup) {
            NavigationStack {
                GroupCreateView { chat in app.openChat = chat }
                    .environmentObject(app)
            }
        }
        .sheet(isPresented: $showScanner) {
            ScannerView { text in
                if !text.isEmpty { app.show(text) }
            }
        }
        .confirmationDialog(Tr("删除这个会话？"),
                            isPresented: Binding(
                                get: { deleteTarget != nil },
                                set: { if !$0 { deleteTarget = nil } }),
                            titleVisibility: .visible) {
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

    private var chatList: some View {
        List {
            Section {
                ForEach(chats) { chat in
                    Button { app.openChat = chat } label: {
                        AppleChatRow(chat: chat)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 9, leading: 14, bottom: 9, trailing: 14))
                    .listRowBackground(AN.rowBg)
                    .contextMenu {
                        Button {
                            Task {
                                _ = await API.shared.setPinned(chatId: chat.id, pinned: !(chat.pinned == true))
                                await app.loadChats()
                            }
                        } label: {
                            Label(chat.pinned == true ? Tr("取消置顶") : Tr("置顶聊天"), systemImage: "pin")
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteTarget = chat
                        } label: {
                            Label(Tr("删除"), systemImage: "trash")
                        }
                        Button {
                            Task {
                                await API.shared.markUnread(chatId: chat.id)
                                await app.loadChats()
                            }
                        } label: {
                            Label(Tr("未读"), systemImage: "envelope.badge")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            Task {
                                _ = await API.shared.setPinned(chatId: chat.id, pinned: !(chat.pinned == true))
                                await app.loadChats()
                            }
                        } label: {
                            Label(chat.pinned == true ? Tr("取消置顶") : Tr("置顶"), systemImage: "pin")
                        }
                        .tint(.orange)
                        Button {
                            Task {
                                _ = await API.shared.setMuted(chatId: chat.id, muted: !(chat.muted == true))
                                await app.loadChats()
                            }
                        } label: {
                            Label(chat.muted == true ? Tr("取消免打扰") : Tr("免打扰"),
                                  systemImage: "bell.slash")
                        }
                        .tint(.gray)
                    }
                }
            } header: {
                HStack {
                    Text(app.offline ? Tr("未连接") : "\(app.chats.reduce(0) { $0 + $1.unreadCount }) 条未读")
                    Spacer()
                    if filter > 0 {
                        Button(Tr(filters[filter])) { filter = 0 }
                            .font(.caption)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await app.loadChats() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(query.isEmpty ? Tr("暂无会话") : Tr("没有找到相关会话"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AppleChatRow: View {
    let chat: Chat

    var body: some View {
        HStack(spacing: 12) {
            Avatar(path: chat.avatar ?? "", size: 48, radius: 14, level: chat.qqLevel ?? 0)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(chat.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if chat.pinned == true {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 4)
                    Text(TimeFmt.list(chat.lastMessage?.createdAt ?? chat.updatedAt))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 6) {
                    if chat.muted == true {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    Text(chat.lastMessage?.preview ?? "")
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if chat.unreadCount > 0 {
                        Text(chat.unreadCount > 99 ? "99+" : "\(chat.unreadCount)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 19, minHeight: 19)
                            .background(Capsule().fill(chat.muted == true ? Color.secondary : AN.accent))
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }
}

private struct AppleContactGroup: Identifiable {
    let id: String
    let users: [User]
}

private struct AppleContactsView: View {
    @EnvironmentObject private var app: AppState
    @State private var query = ""
    @State private var showNewFriends = false
    @State private var showQR = false

    private var contacts: [User] {
        app.contacts
            .filter {
                query.isEmpty
                    || $0.name.localizedCaseInsensitiveContains(query)
                    || ($0.username ?? "").localizedCaseInsensitiveContains(query)
            }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var groups: [AppleContactGroup] {
        let grouped = Dictionary(grouping: contacts) { user -> String in
            guard let first = user.name.first else { return "#" }
            let s = String(first).uppercased()
            return s.range(of: "[A-Z]", options: .regularExpression) == nil ? "#" : s
        }
        return grouped.keys.sorted().map { AppleContactGroup(id: $0, users: grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showNewFriends = true } label: {
                        Label(Tr("新的朋友"), systemImage: "person.badge.plus")
                    }
                    NavigationLink {
                        GroupListView { chat in app.openChat = chat }
                            .environmentObject(app)
                    } label: {
                        Label(Tr("群聊"), systemImage: "person.2")
                    }
                    NavigationLink {
                        AppleStarFriendsView().environmentObject(app)
                    } label: {
                        Label(Tr("星标朋友"), systemImage: "star")
                    }
                    Button { showQR = true } label: {
                        Label(Tr("我的二维码"), systemImage: "qrcode")
                    }
                }

                ForEach(groups) { group in
                    Section(group.id) {
                        ForEach(group.users) { user in
                            NavigationLink {
                                ContactCardView(
                                    user: user,
                                    onOpenChat: { chat in app.openChat = chat },
                                    onOpenMoments: { _ in }
                                )
                                .environmentObject(app)
                            } label: {
                                HStack(spacing: 12) {
                                    Avatar(path: user.avatarPath, size: 40, radius: 12,
                                           level: user.qqLevel ?? 0)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(user.groupName)
                                            .font(.system(size: 16, weight: .medium))
                                        Text(user.status?.isEmpty == false ? user.status! : "@" + (user.username ?? ""))
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AN.groupedBg.ignoresSafeArea())
            .navigationTitle(C.tabText1)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Tr("搜索联系人"))
            .refreshable { await app.loadContacts() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showNewFriends = true } label: {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showNewFriends) {
            NavigationStack { NewFriendsView().environmentObject(app) }
        }
        .sheet(isPresented: $showQR) {
            NavigationStack { MyQRView().environmentObject(app) }
        }
    }
}

private struct AppleStarFriendsView: View {
    @EnvironmentObject private var app: AppState
    @State private var ids: [String] = []

    private var users: [User] {
        app.contacts.filter { ids.contains($0.id) }
    }

    var body: some View {
        List {
            if users.isEmpty {
                ContentUnavailableViewCompat(
                    title: Tr("还没有星标朋友"),
                    systemImage: "star"
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(users) { user in
                    NavigationLink {
                        ContactCardView(
                            user: user,
                            onOpenChat: { chat in app.openChat = chat },
                            onOpenMoments: { _ in }
                        )
                        .environmentObject(app)
                    } label: {
                        HStack(spacing: 12) {
                            Avatar(path: user.avatarPath, size: 40, radius: 12,
                                   level: user.qqLevel ?? 0)
                            Text(user.groupName)
                        }
                    }
                }
            }
        }
        .navigationTitle(Tr("星标朋友"))
        .task { ids = (try? await API.shared.starredFriends()) ?? [] }
    }
}

private struct AppleWorldView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        MomentsView().environmentObject(app)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Tr("生活圈"))
                                Text(Tr("朋友的新鲜动态"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "photo.on.rectangle.angled")
                        }
                    }
                }

                Section(Tr("内容")) {
                    NavigationLink {
                        OfficialAccountsView().environmentObject(app)
                    } label: {
                        Label(Tr("公众号"), systemImage: "megaphone")
                    }
                }

                Section(Tr("服务")) {
                    NavigationLink {
                        MiniAppsView().environmentObject(app)
                    } label: {
                        Label(Tr("小程序"), systemImage: "square.grid.2x2")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AN.groupedBg.ignoresSafeArea())
            .navigationTitle(C.tabText2)
        }
    }
}

private struct AppleMeView: View {
    @EnvironmentObject private var app: AppState
    @State private var showAccounts = false
    @State private var showQR = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showAccounts = true } label: {
                        HStack(spacing: 14) {
                            Avatar(path: app.me?.avatarPath ?? "", size: 60, radius: 18,
                                   level: app.me?.qqLevel ?? 0)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(app.me?.groupName ?? Tr("星言用户"))
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text("@" + (app.me?.username ?? "-"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(app.me?.moodText?.isEmpty == false
                                     ? app.me!.moodText!
                                     : Tr("记录此刻，也连接远方"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    NavigationLink {
                        AIPageView().environmentObject(app)
                    } label: {
                        Label(Tr("小星 AI"), systemImage: "sparkles")
                    }
                    NavigationLink {
                        FavoritesView().environmentObject(app)
                    } label: {
                        Label(Tr("收藏与备忘"), systemImage: "bookmark")
                    }
                    NavigationLink {
                        WalletView().environmentObject(app)
                    } label: {
                        Label(Tr("钱包"), systemImage: "wallet.pass")
                    }
                }

                Section {
                    NavigationLink {
                        SettingsView().environmentObject(app)
                    } label: {
                        Label(Tr("设置"), systemImage: "gearshape")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AN.groupedBg.ignoresSafeArea())
            .navigationTitle(C.tabText3)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showQR = true } label: {
                        Image(systemName: "qrcode")
                    }
                }
            }
        }
        .sheet(isPresented: $showAccounts) {
            NavigationStack { SwitchAccountView().environmentObject(app) }
        }
        .sheet(isPresented: $showQR) {
            NavigationStack { MyQRView().environmentObject(app) }
        }
    }
}

private struct ContentUnavailableViewCompat: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
