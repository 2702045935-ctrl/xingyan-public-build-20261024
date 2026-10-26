import SwiftUI
import UIKit

private enum OrbitStyle {
    static let canvas = Color.dyn(0xF5F4F0, 0x080A09)
    static let raised = Color.dyn(0xFFFFFF, 0x111513)
    static let field = Color.dyn(0xEAE8E2, 0x171B19)
    static let ink = Color.dyn(0x17201C, 0xEFF4F1)
    static let secondary = Color.dyn(0x626B66, 0xA8B2AD)
    static let tertiary = Color.dyn(0x929994, 0x727C77)
    static let divider = Color.dyn(0xE2DFD7, 0x232925)
    static let jade = Color.dyn(0x176A57, 0x63C6A5)
    static let jadeSoft = Color.dyn(0xDCEFE8, 0x173A31)
    static let gold = Color.dyn(0xC18A32, 0xE3B464)
}

struct OrbitChatsPage: View {
    @EnvironmentObject private var app: AppState
    @State private var query = ""
    @State private var filter = 0
    @State private var showAccounts = false
    @State private var showScanner = false
    @State private var showGroupCreate = false
    @State private var deleteTarget: Chat?

    private let filters = ["全部", "未读", "群聊", "服务"]

    private var chats: [Chat] {
        var rows = app.chats.filter { chat in
            let title = (chat.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !chat.id.isEmpty else { return false }
            return !title.isEmpty || chat.lastMessage != nil || !(chat.avatar ?? "").isEmpty
        }
        switch filter {
        case 1:
            rows = rows.filter { $0.unreadCount > 0 || $0.flagged == true }
        case 2:
            rows = rows.filter { $0.type == "group" || ($0.memberCount ?? 0) > 2 }
        case 3:
            rows = rows.filter { !($0.oaId ?? "").isEmpty || $0.oaDigest == true || ($0.botRank ?? -1) >= 0 }
        default:
            break
        }
        if !query.isEmpty {
            rows = rows.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || ($0.lastMessage?.preview ?? "").localizedCaseInsensitiveContains(query)
            }
        }
        return rows
    }

    private var unreadTotal: Int {
        app.chats.reduce(0) { $0 + $1.unreadCount }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OrbitHeader(
                    name: app.me?.name ?? Tr("星言"),
                    subtitle: app.offline ? Tr("离线") : (unreadTotal > 0 ? "\(unreadTotal) 条未读消息" : Tr("消息已读完")),
                    avatar: app.me?.avatarPath ?? "",
                    onAvatar: { showAccounts = true },
                    onScan: { showScanner = true },
                    onAdd: { showGroupCreate = true }
                )

                OrbitSearchField(text: $query)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)

                OrbitFilterBar(filters: filters, selection: $filter)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                Rectangle()
                    .fill(OrbitStyle.divider)
                    .frame(height: 0.5)

                content
            }
            .background(OrbitStyle.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showAccounts) {
            NavigationStack { SwitchAccountView().environmentObject(app) }
        }
        .sheet(isPresented: $showGroupCreate) {
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
                    LocalStore.clearChat(chat.id)
                    await app.loadChats()
                }
            }
            Button(Tr("取消"), role: .cancel) { deleteTarget = nil }
        }
    }

    @ViewBuilder
    private var content: some View {
        if app.loadingChats && app.chats.isEmpty {
            Spacer()
            ProgressView(Tr("正在加载会话…"))
                .tint(OrbitStyle.jade)
                .foregroundStyle(OrbitStyle.secondary)
            Spacer()
        } else if chats.isEmpty {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: "circle.dotted")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(OrbitStyle.tertiary)
                Text(query.isEmpty ? Tr("暂无会话") : Tr("没有找到相关会话"))
                    .font(.system(size: 14))
                    .foregroundStyle(OrbitStyle.secondary)
            }
            Spacer()
        } else {
            List {
                ForEach(chats) { chat in
                    Button { app.openChat = chat } label: {
                        OrbitChatRow(chat: chat)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparatorTint(OrbitStyle.divider)
                    .listRowBackground(OrbitStyle.canvas)
                    .contextMenu {
                        contextActions(chat)
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
                        .tint(OrbitStyle.jade)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            togglePin(chat)
                        } label: {
                            Label(chat.pinned == true ? Tr("取消置顶") : Tr("置顶"),
                                  systemImage: "pin")
                        }
                        .tint(OrbitStyle.gold)
                        Button {
                            toggleMute(chat)
                        } label: {
                            Label(chat.muted == true ? Tr("取消免打扰") : Tr("免打扰"),
                                  systemImage: "bell.slash")
                        }
                        .tint(OrbitStyle.secondary)
                    }
                }

                Color.clear
                    .frame(height: 84)
                    .listRowSeparator(.hidden)
                    .listRowBackground(OrbitStyle.canvas)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(OrbitStyle.canvas)
            .refreshable { await app.loadChats() }
        }
    }

    @ViewBuilder
    private func contextActions(_ chat: Chat) -> some View {
        Button { togglePin(chat) } label: {
            Label(chat.pinned == true ? Tr("取消置顶") : Tr("置顶聊天"), systemImage: "pin")
        }
        Button { toggleMute(chat) } label: {
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

    private func togglePin(_ chat: Chat) {
        Task {
            _ = await API.shared.setPinned(chatId: chat.id, pinned: !(chat.pinned == true))
            await app.loadChats()
        }
    }

    private func toggleMute(_ chat: Chat) {
        Task {
            _ = await API.shared.setMuted(chatId: chat.id, muted: !(chat.muted == true))
            await app.loadChats()
        }
    }
}

private struct OrbitHeader: View {
    let name: String
    let subtitle: String
    let avatar: String
    let onAvatar: () -> Void
    let onScan: () -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onAvatar) {
                Avatar(path: avatar, size: 38, radius: 13)
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(OrbitStyle.jade.opacity(0.45), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("切换账号"))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(name)
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(OrbitStyle.ink)
                        .lineLimit(1)
                    Circle()
                        .fill(OrbitStyle.jade)
                        .frame(width: 5, height: 5)
                        .offset(y: 1)
                }
                Text(subtitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(OrbitStyle.secondary)
            }

            Spacer(minLength: 8)

            OrbitHeaderButton(symbol: "qrcode.viewfinder", action: onScan)
            OrbitHeaderButton(symbol: "plus", action: onAdd)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 7)
    }
}

private struct OrbitHeaderButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(OrbitStyle.ink)
                .frame(width: 36, height: 36)
                .background(Circle().fill(OrbitStyle.field))
                .overlay(Circle().stroke(OrbitStyle.divider, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }
}

private struct OrbitSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(OrbitStyle.tertiary)
            TextField(Tr("搜索消息与联系人"), text: $text)
                .font(.system(size: 14))
                .foregroundStyle(OrbitStyle.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(OrbitStyle.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(OrbitStyle.field)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(OrbitStyle.divider, lineWidth: 0.5)
        )
    }
}

private struct OrbitFilterBar: View {
    let filters: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 22) {
            ForEach(filters.indices, id: \.self) { index in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        selection = index
                    }
                } label: {
                    VStack(spacing: 5) {
                        Text(Tr(filters[index]))
                            .font(.system(size: 12.5,
                                          weight: selection == index ? .semibold : .regular))
                            .foregroundStyle(selection == index
                                             ? OrbitStyle.ink
                                             : OrbitStyle.tertiary)
                        Capsule()
                            .fill(selection == index ? OrbitStyle.jade : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 30)
    }
}

private struct OrbitChatRow: View {
    let chat: Chat

    var body: some View {
        HStack(spacing: 12) {
            Avatar(path: chat.avatar ?? "", size: 50, radius: 16, level: chat.qqLevel ?? 0)
                .overlay(alignment: .topTrailing) {
                    if chat.pinned == true {
                        Circle()
                            .fill(OrbitStyle.gold)
                            .frame(width: 7, height: 7)
                            .overlay(Circle().stroke(OrbitStyle.canvas, lineWidth: 1.5))
                            .offset(x: 2, y: -2)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if chat.unreadCount > 0 {
                        Text(chat.unreadCount > 99 ? "99+" : "\(chat.unreadCount)")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(chat.muted == true ? OrbitStyle.tertiary : Color.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Capsule().fill(chat.muted == true
                                                        ? OrbitStyle.field
                                                        : OrbitStyle.jade))
                            .overlay(Capsule().stroke(OrbitStyle.canvas, lineWidth: 1.4))
                            .offset(x: 4, y: 3)
                    }
                }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text(chat.name)
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(OrbitStyle.ink)
                        .lineLimit(1)
                    if chat.pinned == true {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8.5))
                            .foregroundStyle(OrbitStyle.gold)
                    }
                    Spacer(minLength: 4)
                    Text(TimeFmt.list(chat.lastMessage?.createdAt ?? chat.updatedAt))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(OrbitStyle.tertiary)
                }

                HStack(spacing: 5) {
                    if chat.muted == true {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(OrbitStyle.tertiary)
                    }
                    Text(chat.lastMessage?.preview ?? "")
                        .font(.system(size: 12.5))
                        .foregroundStyle(OrbitStyle.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}
