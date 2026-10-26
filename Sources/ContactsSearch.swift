import SwiftUI

enum ContactSearchHistory {
    private static let key = "chris.contact.search.history"
    static func load() -> [String] {
        (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
    }
    static func add(_ q: String) {
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var list = load().filter { $0 != t }
        list.insert(t, at: 0)
        UserDefaults.standard.set(Array(list.prefix(8)), forKey: key)
    }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

func highlightMatch(_ text: String, _ query: String) -> Text {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return Text(text) }
    var out = Text("")
    var rest = Substring(text)
    while let r = rest.range(of: q, options: [.caseInsensitive]) {
        out = out + Text(String(rest[rest.startIndex..<r.lowerBound]))
        out = out + Text(String(rest[r])).foregroundColor(C.green)
        rest = rest[r.upperBound...]
    }
    return out + Text(String(rest))
}

struct ContactsSearchView: View {

    var onPickUser: (User) -> Void

    var onPickChat: (Chat) -> Void
    var onCancel: () -> Void

    @EnvironmentObject var app: AppState
    @State private var q = ""
    @State private var scope = 0
    @State private var history: [String] = ContactSearchHistory.load()
    @FocusState private var focused: Bool

    private func match(_ u: User) -> Bool {
        let key = q.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key.isEmpty { return false }
        if u.name.lowercased().contains(key) { return true }
        if let un = u.username, un.lowercased().contains(key) { return true }
        if pinyinInitial(u.name).lowercased().contains(key) { return true }
        return false
    }
    private var people: [User] {
        guard scope != 2 else { return [] }
        return app.contacts.filter(match).sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
    private var groups: [Chat] {
        guard scope != 1 else { return [] }
        let key = q.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return [] }
        return app.chats.filter { ($0.type ?? "") == "group" && ($0.title ?? "").lowercased().contains(key) }
    }
    private var nothingFound: Bool {
        !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && people.isEmpty && groups.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {

            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    SVGIcon(markup: I.searchSmall, size: 16, color: C.searchIcon)
                    TextField("", text: $q, prompt: Text(Tr("搜索")).foregroundColor(C.searchIcon))
                        .font(pf(16))
                        .foregroundColor(C.label)
                        .focused($focused)
                        .submitLabel(.search)
                        .onSubmit { if !q.isEmpty { ContactSearchHistory.add(q); history = ContactSearchHistory.load() } }
                    if !q.isEmpty {
                        Button { q = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundColor(C.searchIcon)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(C.searchBg))

                Button(Tr("取消")) { onCancel() }
                    .font(pf(16))
                    .foregroundColor(C.label)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, L.safeTop)
            .padding(.bottom, 8)
            .background(C.chatsTopBg.ignoresSafeArea(edges: .top))

            if !q.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(["全部", "联系人", "群聊"].enumerated()), id: \.offset) { idx, name in
                        Button {
                            scope = idx
                        } label: {
                            Text(Tr(name))
                                .font(pf(13))
                                .foregroundColor(scope == idx ? .white : C.label)
                                .padding(.horizontal, 12)
                                .frame(height: 28)
                                .background(Capsule().fill(scope == idx ? C.green : C.cardBg))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            ScrollView {
                VStack(spacing: 0) {
                    if q.isEmpty {
                        if history.isEmpty {
                            VStack(spacing: 8) {
                                SVGIcon(markup: I.searchBig, size: 42, color: C.subLabel)
                                Text(Tr("搜索联系人 / 群聊")).font(pf(14)).foregroundColor(C.subLabel)
                                Text(Tr("备注、昵称、账号、拼音首字母都能搜")).font(pf(12.5)).foregroundColor(C.subLabel)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        } else {
                            HStack {
                                Text(Tr("最近搜索")).font(pf(13)).foregroundColor(C.subLabel)
                                Spacer(minLength: 0)
                                Button {
                                    ContactSearchHistory.clear()
                                    history = []
                                } label: {
                                    Text(Tr("清空")).font(pf(13)).foregroundColor(C.subLabel)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 34)
                            ForEach(history, id: \.self) { h in
                                Button {
                                    q = h
                                } label: {
                                    HStack(spacing: 8) {
                                        SVGIcon(markup: I.searchSmall, size: 15, color: C.subLabel)
                                        Text(h).font(pf(15)).foregroundColor(C.label)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(height: 46)
                                    .background(C.cardBg)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                HairLine(inset: 16)
                            }
                        }
                    } else if nothingFound {
                        VStack(spacing: 8) {
                            SVGIcon(markup: I.searchBig, size: 42, color: C.subLabel)
                            Text(Tr("没有找到") + "「" + q + "」" + Tr("相关的联系人")).font(pf(14)).foregroundColor(C.subLabel)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        if !people.isEmpty {
                            groupHeader(Tr("联系人") + "（\(people.count)）")
                            ForEach(people, id: \.id) { u in
                                Button {
                                    ContactSearchHistory.add(q)
                                    onPickUser(u)
                                } label: {
                                    HStack(spacing: L.ctGap) {
                                        Avatar(path: u.avatarPath, size: L.ctAvatar, radius: 6)
                                        VStack(alignment: .leading, spacing: 2) {
                                            highlightMatch(u.name, q)
                                                .font(pf(L.ctNameSize))
                                                .foregroundColor(C.label)
                                            if let un = u.username, !un.isEmpty {
                                                highlightMatch(un, q)
                                                    .font(pf(13))
                                                    .foregroundColor(C.subLabel)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(height: L.ctRowH)
                                    .background(C.cardBg)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                HairLine(inset: L.ctTextX)
                            }
                        }
                        if !groups.isEmpty {
                            groupHeader(Tr("群聊") + "（\(groups.count)）")
                            ForEach(groups, id: \.id) { c in
                                Button {
                                    ContactSearchHistory.add(q)
                                    onPickChat(c)
                                } label: {
                                    HStack(spacing: L.ctGap) {
                                        Avatar(path: c.avatar ?? "", size: L.ctAvatar, radius: 6)
                                        highlightMatch(c.title ?? "", q)
                                            .font(pf(L.ctNameSize))
                                            .foregroundColor(C.label)
                                        Spacer(minLength: 0)
                                        if let n = c.memberCount { Text("\(n)").font(pf(13)).foregroundColor(C.subLabel) }
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(height: L.ctRowH)
                                    .background(C.cardBg)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                HairLine(inset: L.ctTextX)
                            }
                        }
                    }
                    Spacer().frame(height: 30)
                }
            }
            .background(C.pageBg)
        }
        .background(C.chatsTopBg.ignoresSafeArea(edges: .top))
        .onAppear {
            history = ContactSearchHistory.load()
            focused = true
        }
    }

    private func groupHeader(_ text: String) -> some View {
        HStack {
            Text(text).font(pf(13)).foregroundColor(C.subLabel)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 32)
        .background(C.pageBg)
    }
}
