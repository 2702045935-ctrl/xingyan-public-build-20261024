import SwiftUI

private struct NoteRecord: Identifiable, Codable, Hashable {
    let id: String
    var content: String
    var title: String
    var createdAt: String
    var updatedAt: String
    var pinned: Bool

    var isLocal: Bool { id.hasPrefix("local-") }

    init?(favorite item: [String: Any]) {
        guard ((item["kind"] as? String) ?? "text") == "text",
              let id = item["id"] as? String, !id.isEmpty else { return nil }
        let from = ((item["from"] as? String)
            ?? (item["fromName"] as? String)
            ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard from.isEmpty else { return nil }

        let rawContent = (item["content"] as? String) ?? ""
        let title = (item["title"] as? String) ?? ""
        let at = (item["at"] as? String) ?? ""
        self.id = id
        self.content = rawContent
        self.title = Self.displayTitle(title: title, content: rawContent)
        self.createdAt = at
        self.updatedAt = (item["updatedAt"] as? String) ?? at
        self.pinned = (item["pinned"] as? Bool) == true
    }

    init(pendingContent content: String, title: String) {
        let now = ISO8601DateFormatter().string(from: Date())
        self.id = "local-" + UUID().uuidString
        self.content = content
        self.title = Self.displayTitle(title: title, content: content)
        self.createdAt = now
        self.updatedAt = now
        self.pinned = false
    }

    var preview: String {
        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var skippedHeading = false
        var lines: [String] = []
        for raw in content.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if !skippedHeading, line == heading {
                skippedHeading = true
                continue
            }
            if line.hasPrefix("[图]") {
                lines.append(Tr("［图片］"))
            } else {
                lines.append(line)
            }
            if lines.joined(separator: "\n").count >= 180 { break }
        }
        return lines.joined(separator: "\n")
    }

    var imagePath: String? {
        for line in content.components(separatedBy: "\n") where line.hasPrefix("[图]") {
            let path = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty { return path }
        }
        return nil
    }

    var checklistSummary: (done: Int, total: Int)? {
        let lines = content.components(separatedBy: "\n")
        let done = lines.filter { $0.hasPrefix("☑") }.count
        let total = lines.filter { $0.hasPrefix("☐") || $0.hasPrefix("☑") }.count
        return total > 0 ? (done, total) : nil
    }

    private static func displayTitle(title: String, content: String) -> String {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { return clean }
        return content.components(separatedBy: "\n")
            .first(where: {
                !$0.hasPrefix("[图]")
                    && !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
            .map { String($0.prefix(60)) }
            ?? Tr("新建备忘录")
    }
}

private enum NoteScope: String, CaseIterable, Identifiable {
    case all = "全部备忘录"
    case pinned = "已置顶"
    var id: String { rawValue }
}

private enum NoteSort: String, CaseIterable, Identifiable {
    case edited = "按编辑日期"
    case created = "按创建日期"
    case title = "按标题"
    var id: String { rawValue }
}

private enum NotesCache {
    private static func key(_ userId: String) -> String {
        "chris.notes.system.cache.v1." + userId
    }

    static func load(userId: String) -> [NoteRecord] {
        guard !userId.isEmpty,
              let data = UserDefaults.standard.data(forKey: key(userId)),
              let records = try? JSONDecoder().decode([NoteRecord].self, from: data) else {
            return []
        }
        return records
    }

    static func save(_ records: [NoteRecord], userId: String) {
        guard !userId.isEmpty,
              let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key(userId))
    }
}

struct NotesWorkspaceView: View {
    @EnvironmentObject private var app: AppState

    @State private var notes: [NoteRecord] = []
    @State private var deletedIds: Set<String> = []
    @State private var loading = true
    @State private var didLoadCache = false
    @State private var loadFailed = false
    @State private var query = ""
    @State private var scope: NoteScope = .all
    @State private var sort: NoteSort = .edited
    @State private var showCompose = false
    @State private var showFavorites = false
    @State private var selectedNote: NoteRecord?

    private var accountKey: String { app.me?.id ?? "" }

    private var filteredNotes: [NoteRecord] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let searched = notes.filter { note in
            if scope == .pinned && !note.pinned { return false }
            guard !search.isEmpty else { return true }
            return note.title.localizedCaseInsensitiveContains(search)
                || note.content.localizedCaseInsensitiveContains(search)
        }
        return ordered(searched)
    }

    private var pinnedNotes: [NoteRecord] {
        filteredNotes.filter(\.pinned)
    }

    private var regularGroups: [(String, [NoteRecord])] {
        let regular = filteredNotes.filter { !$0.pinned }
        var groups: [(String, [NoteRecord])] = []
        for note in regular {
            let title = groupTitle(note)
            if groups.last?.0 == title {
                var group = groups.removeLast()
                group.1.append(note)
                groups.append(group)
            } else {
                groups.append((title, [note]))
            }
        }
        return groups
    }

    var body: some View {
        List {
            quickComposeSection

            if loading && notes.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 28)
                }
            } else if filteredNotes.isEmpty {
                emptySection
            } else {
                if !pinnedNotes.isEmpty {
                    Section {
                        ForEach(pinnedNotes) { note in
                            noteRow(note)
                        }
                    } header: {
                        Label(Tr("已置顶"), systemImage: "pin.fill")
                    }
                }

                ForEach(regularGroups, id: \.0) { group in
                    Section(group.0) {
                        ForEach(group.1) { note in
                            noteRow(note)
                        }
                    }
                }

                if loadFailed {
                    Section {
                        Label(Tr("暂时无法同步，正在显示上次内容"),
                              systemImage: "wifi.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("备忘录"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(Tr("搜索备忘录"))
        )
        .refreshable { await load() }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Picker(Tr("显示"), selection: $scope) {
                        ForEach(NoteScope.allCases) { item in
                            Text(Tr(item.rawValue)).tag(item)
                        }
                    }

                    Picker(Tr("排序方式"), selection: $sort) {
                        ForEach(NoteSort.allCases) { item in
                            Text(Tr(item.rawValue)).tag(item)
                        }
                    }

                    Divider()

                    Button {
                        showFavorites = true
                    } label: {
                        Label(Tr("收藏内容"), systemImage: "star")
                    }

                    if loadFailed {
                        Button {
                            Task { await load() }
                        } label: {
                            Label(Tr("重新同步"), systemImage: "arrow.clockwise")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(Tr("备忘录选项"))

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showCompose = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel(Tr("新建备忘录"))
            }
        }
        .task {
            restoreCacheIfNeeded()
            if notes.isEmpty { await load() }
        }
        .sheet(isPresented: $showCompose) {
            FavoriteNoteComposeSheet { body, title, _ in
                let pending = NoteRecord(pendingContent: body, title: title)
                notes.insert(pending, at: 0)
                NotesCache.save(notes, userId: accountKey)
                Task {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    await load()
                }
            }
            .environmentObject(app)
        }
        .sheet(item: $selectedNote) { note in
            FavoriteNoteDetailSheet(
                id: note.id,
                content: note.content,
                createdAt: note.updatedAt,
                pinned: note.pinned
            ) {
                Task { await load() }
            }
            .environmentObject(app)
        }
        .sheet(isPresented: $showFavorites) {
            NavigationStack {
                FavoritesView()
                    .environmentObject(app)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(Tr("完成")) { showFavorites = false }
                        }
                    }
            }
        }
    }

    private var quickComposeSection: some View {
        Section {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showCompose = true
            } label: {
                HStack(spacing: 13) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.yellow.gradient)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Tr("新建备忘录"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(Tr("快速记录文字、清单、照片和扫描文稿"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var emptySection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: query.isEmpty ? "note.text" : "magnifyingglass")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(query.isEmpty ? Tr("暂无备忘录") : Tr("没有找到备忘录"))
                    .font(.headline)
                Text(query.isEmpty
                     ? Tr("点右上角开始记录，内容会同步到自己的设备")
                     : Tr("换一个关键词试试"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
            .listRowBackground(Color.clear)
        }
    }

    private func noteRow(_ note: NoteRecord) -> some View {
        Button {
            guard !note.isLocal else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            selectedNote = note
        } label: {
            HStack(alignment: .top, spacing: 12) {
                if let path = note.imagePath {
                    RemoteImage(path: path, mode: .fill, maxSide: 240)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(note.title.isEmpty ? Tr("新建备忘录") : note.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if note.pinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Text(TimeFmt.listApple(note.updatedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if !note.preview.isEmpty {
                        Text(note.preview)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    if let list = note.checklistSummary {
                        Label("\(list.done) / \(list.total)", systemImage: "checklist")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !note.isLocal {
                Button {
                    togglePinned(note)
                } label: {
                    Label(note.pinned ? Tr("取消置顶") : Tr("置顶"),
                          systemImage: note.pinned ? "pin.slash.fill" : "pin.fill")
                }
                .tint(.orange)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !note.isLocal {
                Button(role: .destructive) {
                    delete(note)
                } label: {
                    Label(Tr("删除"), systemImage: "trash.fill")
                }
            }
        }
        .contextMenu {
            if !note.isLocal {
                Button {
                    togglePinned(note)
                } label: {
                    Label(note.pinned ? Tr("取消置顶") : Tr("置顶"),
                          systemImage: note.pinned ? "pin.slash" : "pin")
                }

                Button(role: .destructive) {
                    delete(note)
                } label: {
                    Label(Tr("删除"), systemImage: "trash")
                }
            }
        }
    }

    private func restoreCacheIfNeeded() {
        guard !didLoadCache else { return }
        didLoadCache = true
        let cached = NotesCache.load(userId: accountKey)
        if !cached.isEmpty {
            notes = cached
            loading = false
        }
    }

    private func load() async {
        restoreCacheIfNeeded()
        if notes.isEmpty { loading = true }
        defer { loading = false }

        guard let fresh = await API.shared.favoritesResult() else {
            loadFailed = true
            return
        }

        let mapped = fresh.compactMap(NoteRecord.init(favorite:))
            .filter { !deletedIds.contains($0.id) }
        notes = mapped
        loadFailed = false
        NotesCache.save(mapped, userId: accountKey)
    }

    private func togglePinned(_ note: NoteRecord) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        let desired = !notes[index].pinned
        notes[index].pinned = desired
        NotesCache.save(notes, userId: accountKey)
        Task { @MainActor in
            if !(await API.shared.updateFavorite(id: note.id, pinned: desired)) {
                if let current = notes.firstIndex(where: { $0.id == note.id }) {
                    notes[current].pinned = !desired
                    NotesCache.save(notes, userId: accountKey)
                }
                app.show(Tr("置顶失败，请稍后重试"))
            }
        }
    }

    private func delete(_ note: NoteRecord) {
        deletedIds.insert(note.id)
        notes.removeAll { $0.id == note.id }
        NotesCache.save(notes, userId: accountKey)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task { @MainActor in
            if let error = await API.shared.deleteFavorite(note.id) {
                deletedIds.remove(note.id)
                app.show(error)
                await load()
            }
        }
    }

    private func ordered(_ input: [NoteRecord]) -> [NoteRecord] {
        input.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            switch sort {
            case .edited:
                return noteDate(lhs.updatedAt) > noteDate(rhs.updatedAt)
            case .created:
                return noteDate(lhs.createdAt) > noteDate(rhs.createdAt)
            case .title:
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }
    }

    private func noteDate(_ value: String) -> Date {
        TimeFmt.date(value) ?? .distantPast
    }

    private func groupTitle(_ note: NoteRecord) -> String {
        if sort == .title { return Tr("按标题") }
        let value = sort == .edited ? note.updatedAt : note.createdAt
        guard let date = TimeFmt.date(value) else { return Tr("更早") }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return Tr("今天") }
        if calendar.isDateInYesterday(date) { return Tr("昨天") }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: Date())
        ).day ?? 99
        return days < 7 ? Tr("过去 7 天") : Tr("更早")
    }
}
