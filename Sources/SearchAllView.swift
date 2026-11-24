import SwiftUI

struct SearchAllData: Decodable {
    struct Person: Decodable, Hashable, Identifiable { var id: String; var name: String?; var username: String?; var avatar: String? }
    struct Group: Decodable, Hashable, Identifiable { var id: String; var name: String?; var avatar: String?; var members: Int? }
    struct Post: Decodable, Hashable, Identifiable { var id: String; var author: String?; var content: String?; var images: [String]?; var createdAt: String? }
    struct Video: Decodable, Hashable, Identifiable { var id: String; var title: String?; var cover: String?; var author: String? }
    struct ChatHit: Decodable, Hashable, Identifiable {
        var chatId: String
        var isGroup: Bool?
        var chatTitle: String?
        var peerId: String?
        var messageId: String
        var sender: String?
        var text: String?
        var at: String?
        var id: String { messageId }
    }
    var people: [Person]?
    var groups: [Group]?
    var moments: [Post]?
    var videos: [Video]?
    var messages: [ChatHit]?
    var suggestions: [String]?
}

struct SearchAllView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var q = ""
    @State private var scope = "all"
    @State private var data: SearchAllData?
    @State private var searching = false
    @State private var searchFailed = false
    @State private var history: [String] = ContactSearchHistory.load()
    @FocusState private var focused: Bool
    @State private var task: Task<Void, Never>?

    @State private var pickedUser: User?
    @State private var showMoments = false
    @State private var showChannels = false
    @State private var showPlugins = false
    @State private var showBrowser = false
    @State private var showDrop = false

    private let scopes: [(String, String)] = [
        ("all", "全部"), ("people", "联系人"), ("groups", "群聊"),
        ("moments", "生活圈"), ("videos", "视频号"), ("messages", "聊天记录")
    ]

    private struct ToolHit: Identifiable {
        let id: String
        let title: String
        let sub: String
        let symbol: String
        let keywords: String
    }

    private let tools: [ToolHit] = [
        ToolHit(id: "ai", title: "小星 AI", sub: "问答、创作、联网搜索与文件阅读",
                symbol: "sparkles", keywords: "小星 AI ai 人工智能 星言助手 小星助手 官方助手 电话 通话 语音 问答 创作 搜索 助手 官方工具 工具"),
        ToolHit(id: "browser", title: "内置浏览器", sub: "在星言里搜索和打开网页",
                symbol: "safari", keywords: "内置浏览器 浏览器 网页 网站 打开网页 搜索 官方工具 工具"),
        ToolHit(id: "drop", title: "文件快传", sub: "面对面传照片、视频和文件",
                symbol: "dot.radiowaves.left.and.right", keywords: "文件快传 快传 文件 传文件 文件传输 面对面 传输 官方工具 工具")
    ]

    private var matchedTools: [ToolHit] {
        let key = q.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return [] }
        return tools.filter {
            $0.title.lowercased().contains(key) || $0.keywords.lowercased().contains(key)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppDesign.Spacing.xs) {
                HStack(spacing: 5) {
                    SVGIcon(markup: I.searchSmall, size: 16, color: C.searchIcon)
                    TextField("", text: $q, prompt: Text(Tr("搜索")).foregroundColor(C.searchIcon))
                        .font(pf(16)).foregroundColor(C.label)
                        .focused($focused)
                        .submitLabel(.search)
                        .onSubmit { remember() }
                    if !q.isEmpty {
                        Button { q = ""; data = nil } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundColor(C.searchIcon)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: AppDesign.Control.floatingControlHeight)
                .background(RoundedRectangle(cornerRadius: AppDesign.Radius.small, style: .continuous).fill(C.searchBg))
                Button(Tr("取消")) { dismiss() }
                    .font(pf(16)).foregroundColor(C.label)
                    .buttonStyle(MenuPressStyle())
            }
            .padding(.horizontal, AppDesign.Spacing.sm)
            .padding(.top, L.safeTop)
            .padding(.bottom, AppDesign.Spacing.xs)
            .background(C.chatsTopBg.ignoresSafeArea(edges: .top))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppDesign.Spacing.xs) {
                    ForEach(scopes, id: \.0) { s in
                        Button {
                            scope = s.0
                            runSearch()
                        } label: {
                            Text(Tr(s.1))
                                .font(pf(13))
                                .foregroundColor(scope == s.0 ? .white : C.label)
                                .padding(.horizontal, AppDesign.Spacing.sm)
                                .frame(height: AppDesign.Control.statusHeight)
                                .background(Capsule().fill(scope == s.0 ? C.green : C.cardBg))
                        }
                        .buttonStyle(AppSegmentPressStyle())
                    }
                }
                .padding(.horizontal, AppDesign.Spacing.sm)
            }
            .padding(.vertical, AppDesign.Spacing.xs)

            ScrollView {
                VStack(spacing: 0) {
                    if q.isEmpty {
                        if history.isEmpty {
                            VStack(spacing: AppDesign.Spacing.xs) {
                                SVGIcon(markup: I.searchBig, size: 42, color: C.subLabel)
                                Text(Tr("搜聊天记录、联系人、群聊、朋友圈、视频号")).font(pf(14)).foregroundColor(C.subLabel)
                            }
                            .frame(maxWidth: .infinity).padding(.top, 60)
                        } else {
                            HStack {
                                Text(Tr("最近搜索")).font(pf(13)).foregroundColor(C.subLabel)
                                Spacer(minLength: 0)
                                Button {
                                    ContactSearchHistory.clear(); history = []
                                } label: { Text(Tr("清空")).font(pf(13)).foregroundColor(C.subLabel) }
                                .buttonStyle(MenuPressStyle())
                            }
                            .padding(.horizontal, AppDesign.Spacing.md).frame(height: 34)
                            ForEach(history, id: \.self) { h in
                                Button { q = h; runSearch() } label: {
                                    HStack(spacing: AppDesign.Spacing.xs) {
                                        SVGIcon(markup: I.searchSmall, size: 15, color: C.subLabel)
                                        Text(Tr(h)).font(pf(15)).foregroundColor(C.label)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, AppDesign.Spacing.md).frame(height: 46)
                                    .background(C.cardBg).contentShape(Rectangle())
                                }
                                .buttonStyle(MenuPressStyle())
                                HairLine(inset: 16)
                            }
                        }
                    } else if searching && data == nil {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text(Tr("正在搜索…")).font(pf(13)).foregroundColor(C.subLabel)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 44)
                    } else if searchFailed && data == nil {
                        VStack(spacing: 9) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 30, weight: .light))
                                .foregroundColor(C.subLabel)
                            Text(Tr("搜索暂时不可用"))
                                .font(pf(15, .semibold))
                                .foregroundColor(C.label)
                            Text(Tr("检查网络后再试一次"))
                                .font(AppDesign.Typography.caption)
                                .foregroundColor(C.subLabel)
                            Button(Tr("重新搜索")) { runSearch() }
                                .font(pf(14, .medium))
                                .foregroundColor(C.green)
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .background(C.green.opacity(0.10), in: Capsule())
                                .buttonStyle(MenuPressStyle())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 46)
                    } else {
                        if searching {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity)
                                .padding(.top, AppDesign.Spacing.xs)
                        }
                        if searchFailed {
                            HStack(spacing: AppDesign.Spacing.xs) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(C.orange)
                                Text(Tr("结果可能没有更新"))
                                    .font(AppDesign.Typography.caption)
                                    .foregroundStyle(C.subLabel)
                                Spacer(minLength: 0)
                                Button(Tr("重试")) { runSearch() }
                                    .font(AppDesign.Typography.captionStrong)
                                    .foregroundStyle(C.green)
                                    .buttonStyle(MenuPressStyle())
                            }
                            .padding(.horizontal, AppDesign.Spacing.md)
                            .frame(height: 34)
                            .background(C.orange.opacity(0.07))
                        }
                        results
                    }
                    Spacer().frame(height: AppDesign.Control.sectionHeaderHeight)
                }
            }
            .background(C.pageBg)
        }
        .background(C.chatsTopBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .onAppear { focused = true }
        .onChange(of: q) { _ in runSearch() }
        .sheet(item: $pickedUser) { u in
            NavigationView {
                ContactCardView(user: u,
                                onOpenChat: { chat in
                                    pickedUser = nil
                                    app.openChatViaList(chat)
                                },
                                onOpenMoments: { _ in
                                    pickedUser = nil
                                    showMoments = true
                                })
            }
            .environmentObject(app)
        }
        .fullScreenCover(isPresented: $showMoments) { MomentsView().environmentObject(app) }
        .fullScreenCover(isPresented: $showChannels) { ChannelsView().environmentObject(app) }
        .fullScreenCover(isPresented: $showPlugins) { PluginsView().environmentObject(app) }
        .fullScreenCover(isPresented: $showBrowser) { InAppBrowserView() }
        .fullScreenCover(isPresented: $showDrop) {
            FaceToFaceFileSheet(rows: [],
                                avatar: app.me?.avatarPath ?? "",
                                name: app.me?.name ?? "")
                .environmentObject(app)
        }
    }

    @ViewBuilder private var results: some View {
        let d = data
        let people = d?.people ?? []
        let groups = d?.groups ?? []
        let moments = d?.moments ?? []
        let videos = d?.videos ?? []
        let msgs = d?.messages ?? []
        if people.isEmpty && groups.isEmpty && moments.isEmpty && videos.isEmpty
            && msgs.isEmpty && matchedTools.isEmpty {
            VStack(spacing: AppDesign.Spacing.xs) {
                SVGIcon(markup: I.searchBig, size: 42, color: C.subLabel)
                Text(Tr("没有找到") + "「" + q + "」" + Tr("相关的内容")).font(pf(14)).foregroundColor(C.subLabel)
            }
            .frame(maxWidth: .infinity).padding(.top, 60)
        }
        if !matchedTools.isEmpty {
            header(Tr("功能"), matchedTools.count)
            ForEach(matchedTools) { tool in
                row(tap: {
                    remember()
                    if tool.id == "browser" { showBrowser = true }
                    else if tool.id == "drop" { showDrop = true }
                    else { showPlugins = true }
                }) {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundColor(C.green)
                        .frame(width: 40, height: 40)
                        .background(C.green.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.mini, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        highlightMatch(tool.title, q).font(AppDesign.Typography.bodyLarge).foregroundColor(C.label)
                        Text(tool.sub).font(pf(13)).foregroundColor(C.subLabel).lineLimit(1)
                    }
                }
            }
        }
        if !people.isEmpty {
            header(Tr("联系人"), people.count)
            ForEach(people) { p in
                row(tap: {
                    remember()
                    pickedUser = User(id: p.id)
                }) {
                    Avatar(path: p.avatar ?? "", size: 40, radius: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        highlightMatch(p.name ?? "", q).font(AppDesign.Typography.bodyLarge).foregroundColor(C.label)
                        if let u = p.username, !u.isEmpty {
                            highlightMatch(u, q).font(pf(13)).foregroundColor(C.subLabel)
                        }
                    }
                }
            }
        }
        if !groups.isEmpty {
            header(Tr("群聊"), groups.count)
            ForEach(groups) { g in
                row(tap: {
                    remember()
                    openChat(g.id)
                }) {
                    Avatar(path: g.avatar ?? "", size: 40, radius: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        highlightMatch(g.name ?? "", q).font(AppDesign.Typography.bodyLarge).foregroundColor(C.label)
                        Text(Tr("\((g.members ?? 0)) 人")).font(AppDesign.Typography.caption).foregroundColor(C.subLabel)
                    }
                }
            }
        }
        if !msgs.isEmpty {
            header(Tr("聊天记录"), msgs.count)
            ForEach(msgs) { m in
                row(tap: {
                    remember()
                    openMessage(m)
                }) {
                    Avatar(path: "", size: 40, radius: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(m.chatTitle ?? "").font(pf(15)).foregroundColor(C.label).lineLimit(1)
                            if (m.isGroup ?? false) { Text(Tr("群")).font(pf(11)).foregroundColor(C.subLabel) }
                            Spacer(minLength: 0)
                            Text(shortDate(m.at)).font(pf(12)).foregroundColor(C.subLabel)
                        }
                        highlightMatch(m.text ?? "", q).font(AppDesign.Typography.body).foregroundColor(C.subLabel).lineLimit(1)
                    }
                }
            }
        }
        if !moments.isEmpty {
            header(Tr("朋友圈"), moments.count)
            ForEach(moments) { p in
                row(tap: {
                    remember()
                    showMoments = true
                }) {
                    Avatar(path: "", size: 40, radius: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.author ?? "").font(pf(14)).foregroundColor(C.label)
                        highlightMatch(p.content ?? "", q).font(AppDesign.Typography.body).foregroundColor(C.subLabel).lineLimit(2)
                    }
                }
            }
        }
        if !videos.isEmpty {
            header(Tr("视频号"), videos.count)
            ForEach(videos) { v in
                row(tap: {
                    remember()
                    showChannels = true
                }) {
                    Avatar(path: v.cover ?? "", size: 40, radius: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        highlightMatch(v.title ?? "", q).font(pf(15)).foregroundColor(C.label).lineLimit(1)
                        Text(v.author ?? "").font(AppDesign.Typography.caption).foregroundColor(C.subLabel)
                    }
                }
            }
        }
    }

    private func header(_ t: String, _ n: Int) -> some View {
        HStack {
            Text(t).font(AppDesign.Typography.captionStrong).foregroundColor(C.subLabel)
            Spacer(minLength: 0)
            Text("\(n)").font(pf(11.5, .medium))
                .foregroundColor(C.subLabel.opacity(0.75)).monospacedDigit()
        }
        .padding(.horizontal, AppDesign.Spacing.md).frame(height: AppDesign.Control.smallButtonHeight).background(C.pageBg)
    }

    private func row<Content: View>(tap: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button(action: tap) {
            HStack(spacing: AppDesign.Spacing.sm) {
                content()
                Spacer(minLength: 0)
                Chevron(size: 8, line: 1.4)
            }
            .padding(.horizontal, AppDesign.Spacing.md)
            .frame(minHeight: 56)
            .background(C.cardBg)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                HairLine(inset: 68)
            }
        }
        .buttonStyle(MenuPressStyle())
    }

    private func shortDate(_ s: String?) -> String {
        guard let s = s, s.count >= 16 else { return "" }
        return String(s.prefix(10))
    }

    private func remember() {
        guard !q.isEmpty else { return }
        ContactSearchHistory.add(q)
        history = ContactSearchHistory.load()
    }

    private func openChat(_ id: String) {
        if let c = app.chats.first(where: { $0.id == id }) {
            app.openChatViaList(c)
        } else {
            app.show(Tr("这个会话不在你的列表里"))
        }
    }

    private func openMessage(_ hit: SearchAllData.ChatHit) {
        guard let c = app.chats.first(where: { $0.id == hit.chatId }) else {
            app.show(Tr("这个会话不在你的列表里"))
            return
        }
        app.openChatViaList(c)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            ChatSearchJump.request(chatId: hit.chatId,
                                   messageId: hit.messageId,
                                   seq: nil)
        }
    }

    private func runSearch() {
        task?.cancel()
        let key = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            data = nil
            searchFailed = false
            searching = false
            return
        }
        searchFailed = false
        searching = true
        task = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            let got = try? await API.shared.searchAll(key, scope: scope)
            if Task.isCancelled { return }
            await MainActor.run {
                if let got {
                    data = got
                } else {
                    searchFailed = true
                }
                searching = false
            }
        }
    }
}
