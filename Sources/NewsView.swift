import SwiftUI

private struct NewsTopic: Identifiable {
    let id: String
    let title: String
    let items: [NewsItem]
}

struct NewsFeedView: View {

    var compact: Bool = false

    var refreshToken: Int = 0

    var initialSource: String = "qq"

    var onlyTabs: [NewsChannel]? = nil

    @State private var channels: [NewsChannel] = NewsFeedView.builtinChannels
    @State private var tab = "qq"
    @State private var items: [NewsItem] = []
    @State private var loading = false
    @State private var failed = false

    @State private var loadingTab = ""

    @State private var offset = 0
    @State private var total = 0
    @State private var compactLoadingMore = false
    @State private var compactHasMore = true
    @State private var web: WebURL?

    static let builtinChannels: [NewsChannel] = [
        NewsChannel(id: "qq", label: "热点", desc: "热点榜"),
        NewsChannel(id: "toutiao", label: "头条", desc: "今日头条热榜"),
        NewsChannel(id: "sina", label: "要闻", desc: "新浪滚动新闻"),
        NewsChannel(id: "weibo", label: "热搜", desc: "微博热搜榜"),
        NewsChannel(id: "baidu", label: "百度", desc: "百度热搜榜")
    ]

    private var accent: Color { C.green }
    private var newsPageBg: Color { Color(uiColor: .systemGroupedBackground) }

    var body: some View {
        Group {
            if compact {
                compactFeed
            } else {
                premiumFeed
            }
        }
        .task {
            if tab.isEmpty { tab = initialSource }
            if let only = onlyTabs { channels = only }
            if items.isEmpty { await load(tab) }
        }
        .onChange(of: refreshToken) { _ in Task { await load(tab) } }
        .fullScreenCover(item: $web) { w in
            SafariSheet(url: w.url).ignoresSafeArea()
        }
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppDesign.Spacing.xl) {
                ForEach(channels) { ch in
                    Button { select(ch.id) } label: {
                        VStack(spacing: 5) {
                            Text(Tr(ch.label))
                                .font(pf(16, tab == ch.id ? .semibold : .regular))
                                .foregroundColor(tab == ch.id ? C.label : C.subLabel)
                            RoundedRectangle(cornerRadius: AppDesign.Radius.hairline, style: .continuous)
                                .fill(tab == ch.id ? accent : Color.clear)
                                .frame(width: 20, height: 2.5)
                        }
                        .padding(.top, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppDesign.Spacing.md)
        }
        .background(newsPageBg)
        .overlay(alignment: .bottom) { HairLine() }
    }

    private var premiumFeed: some View {
        ScrollView {
            LazyVStack(spacing: AppDesign.Spacing.lg, pinnedViews: [.sectionHeaders]) {
                Section {
                    if items.isEmpty && loading {
                        premiumLoading
                    } else if items.isEmpty {
                        premiumEmpty
                    } else if isBoard {
                        premiumBoard
                    } else {
                        premiumEditorial
                    }
                } header: {
                    premiumChannelBar
                }
            }
            .padding(.bottom, 34)
        }
        .background(newsPageBg)
        .refreshable { await load(tab) }
    }

    private var compactFeed: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    if items.isEmpty && loading {
                        premiumLoading
                    } else if items.isEmpty {
                        premiumEmpty
                    } else {
                        ForEach(compactTopics) { topic in
                            compactTopic(topic)
                        }
                        if compactHasMore {
                            Color.clear
                                .frame(height: 1)
                                .onAppear {
                                    Task { await loadCompactMore() }
                                }
                        } else {
                            Text(Tr("已经到底了"))
                                .font(pf(12))
                                .foregroundColor(C.time)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 22)
                        }
                    }
                } header: {
                    compactChannelHeader
                }
            }
            .padding(.bottom, 28)
        }
        .background(newsPageBg)
        .refreshable { await load(tab) }
    }

    private var compactChannelHeader: some View {
        HStack(spacing: AppDesign.Spacing.xs) {
            Text(Tr("时刻新闻"))
                .font(pfStyled(size: 18, weight: .semibold))
                .foregroundColor(C.label)
            Text("·")
                .foregroundColor(C.subLabel)
            Text(Tr(channels.first(where: { $0.id == tab })?.label ?? "热点"))
                .font(pfStyled(size: 13, weight: .medium))
                .foregroundColor(C.green)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(C.subLabel)
        }
        .padding(.horizontal, AppDesign.Spacing.md)
        .frame(height: AppDesign.Control.searchHeight)
        .background(newsPageBg)
        .overlay(alignment: .bottom) { HairLine() }
        .onTapGesture {
            guard channels.count > 1 else { return }
            if let next = channels.firstIndex(where: { $0.id == tab }),
               next + 1 < channels.count {
                select(channels[next + 1].id)
            } else if let first = channels.first {
                select(first.id)
            }
        }
    }

    private func compactTopic(_ topic: NewsTopic) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text(topic.title)
                    .font(pfStyled(size: 14, weight: .semibold))
                    .foregroundColor(C.label)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(topic.items.count) " + Tr("条"))
                    .font(pf(11.5))
                    .foregroundColor(C.time)
            }
            .padding(.horizontal, AppDesign.Spacing.md)
            .padding(.top, 17)
            .padding(.bottom, AppDesign.Spacing.xs)

            VStack(spacing: 0) {
                ForEach(Array(topic.items.enumerated()), id: \.element.id) { index, item in
                    Button { open(item) } label: {
                        compactArticleRow(item, index: index)
                    }
                    .buttonStyle(.plain)
                    if index < topic.items.count - 1 {
                        HairLine(inset: 16)
                    }
                }
            }
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppDesign.Radius.control, style: .continuous)
                    .stroke(Color.primary.opacity(0.055), lineWidth: 0.5)
            }
            .padding(.horizontal, AppDesign.Spacing.sm)
            .padding(.bottom, 10)
        }
    }

    private func compactArticleRow(_ item: NewsItem, index: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)")
                .font(pfStyled(size: 12, weight: .semibold))
                .foregroundColor(index == 0 ? C.green : C.time)
                .frame(width: 18, alignment: .leading)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(pfStyled(size: 15.5, weight: .medium))
                    .foregroundColor(C.label)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 5) {
                    Text(item.src)
                    if !timeText(item.at).isEmpty {
                        Text("·")
                        Text(timeText(item.at))
                    }
                }
                .font(pf(11.5))
                .foregroundColor(C.time)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !item.cover.isEmpty {
                RemoteImage(path: item.cover, mode: .fill, maxSide: 420)
                    .frame(width: 62, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.tiny, style: .continuous))
            }
        }
        .padding(.horizontal, AppDesign.Spacing.md)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var compactTopics: [NewsTopic] {
        var groups: [NewsTopic] = []
        var start = 0
        while start < items.count {
            let end = min(items.count, start + 4)
            let slice = Array(items[start..<end])
            let title = slice.first?.src.trimmingCharacters(in: .whitespacesAndNewlines)
            groups.append(NewsTopic(
                id: "topic-\(start)-\(slice.first?.id ?? "")",
                title: title?.isEmpty == false ? title! : Tr("热点"),
                items: slice
            ))
            start = end
        }
        return groups
    }

    @ViewBuilder
    private var premiumChannelBar: some View {
        if channels.count > 1 {
            HStack {
                Menu {
                    ForEach(channels) { channel in
                        Button {
                            select(channel.id)
                        } label: {
                            if channel.id == tab {
                                Label(Tr(channel.label), systemImage: "checkmark")
                            } else {
                                Text(Tr(channel.label))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(Tr(channels.first(where: { $0.id == tab })?.label ?? "热点"))
                            .font(pf(17, .semibold))
                            .foregroundColor(C.label)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(C.subLabel)
                    }
                    .contentShape(Rectangle())
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppDesign.Spacing.md)
            .frame(height: AppDesign.Control.iconControlHeight)
            .background(newsPageBg)
            .overlay(alignment: .bottom) { HairLine() }
        }
    }

    private var premiumLoading: some View {
        VStack(spacing: AppDesign.Spacing.sm) {
            ProgressView()
                .tint(accent)
            Text(Tr("正在整理最新内容…"))
                .font(pfStyled(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 74)
    }

    private var premiumEmpty: some View {
        VStack(spacing: 14) {
            Image(systemName: failed ? "wifi.exclamationmark" : "newspaper")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text(failed ? Tr("暂时没有取到内容") : Tr("这里还没有新闻"))
                .font(pfStyled(size: 17, weight: .semibold))
            Text(failed ? Tr("检查网络后再试一次") : Tr("稍后下拉刷新"))
                .font(pfStyled(size: 13))
                .foregroundStyle(.secondary)
            Button(Tr("重新加载")) { Task { await load(tab) } }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
    }

    private var premiumEditorial: some View {
        let rows = Array(items)
        return VStack(alignment: .leading, spacing: 20) {
            editionHeader
            if let first = rows.first {
                premiumSectionTitle(Tr("今日焦点"), trailing: first.src)
                premiumHero(first)
            }
            if rows.count > 1 {
                premiumSectionTitle(Tr("最新"), trailing: "\(rows.count - 1) " + Tr("条"))
                VStack(spacing: 0) {
                    ForEach(Array(rows.dropFirst())) { item in
                        Button { open(item) } label: {
                            premiumArticleRow(item)
                        }
                        .buttonStyle(.plain)
                        if item.id != rows.last?.id {
                            HairLine(inset: 15)
                        }
                    }
                }
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous)
                        .stroke(Color.primary.opacity(0.065), lineWidth: 0.6)
                }
            }
            premiumFooter
        }
        .padding(.horizontal, 18)
    }

    private var editionHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(Tr("今日简报"))
                    .font(.system(size: 31, weight: .bold, design: .serif))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: "newspaper.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text(editionDateText)
                Text("·")
                Text(Tr("由星联世界编辑更新"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.top, AppDesign.Spacing.xxs)
    }

    private var editionDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Lang.isEnglish ? "en_US" :
                                  (Lang.isRussian ? "ru_RU" : "zh_CN"))
        formatter.dateFormat = Lang.isEnglish ? "EEEE, MMMM d" :
            (Lang.isRussian ? "EEEE, d MMMM" : "M月d日 EEEE")
        return formatter.string(from: Date())
    }

    private func premiumSectionTitle(_ title: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text(trailing)
                .font(pfStyled(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.top, AppDesign.Spacing.xxs)
    }

    private func premiumHero(_ item: NewsItem) -> some View {
        Button { open(item) } label: {
            Group {
                if item.cover.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        premiumTag(item)
                        Text(item.title)
                            .font(.system(size: 26, weight: .bold, design: .serif))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(4)
                        if let summary = item.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.system(size: 15.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        premiumMeta(item, onDark: false)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
                    .background(Color(uiColor: .systemBackground))
                } else {
                    ZStack(alignment: .bottomLeading) {
                        RemoteImage(path: item.cover, mode: .fill, maxSide: 1600)
                            .frame(maxWidth: .infinity)
                            .frame(height: 252)
                            .clipped()
                        LinearGradient(colors: [.clear, .black.opacity(0.16),
                                                .black.opacity(0.90)],
                                       startPoint: .top, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 9) {
                            premiumTag(item, dark: true)
                            Text(item.title)
                                .font(.system(size: 26, weight: .bold, design: .serif))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                                .lineLimit(4)
                            premiumMeta(item, onDark: true)
                        }
                        .padding(AppDesign.Spacing.lg)
                    }
                    .frame(height: 252)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.overlay, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppDesign.Radius.overlay, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.6)
            }
            .shadow(color: Color.black.opacity(0.10), radius: 18, y: 7)
        }
        .buttonStyle(.plain)
    }

    private func premiumArticleRow(_ item: NewsItem) -> some View {
        HStack(alignment: .top, spacing: 13) {
            VStack(alignment: .leading, spacing: 8) {
                premiumMeta(item, onDark: false)
                Text(item.title)
                    .font(.system(size: 17.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                if let summary = item.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !item.tagText.isEmpty {
                    tagChip(item.tagText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !item.cover.isEmpty {
                RemoteImage(path: item.cover, mode: .fill, maxSide: 700)
                    .frame(width: 108, height: 82)
                    .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.compact, style: .continuous))
            }
        }
        .padding(.horizontal, AppDesign.Spacing.md)
        .padding(.vertical, AppDesign.Spacing.md)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func premiumTag(_ item: NewsItem, dark: Bool = false) -> some View {
        if !item.tagText.isEmpty {
            Text(item.tagText)
                .font(pfStyled(size: 11, weight: .semibold))
                .foregroundStyle(dark ? .white : C.red)
                .padding(.horizontal, AppDesign.Spacing.xs)
                .padding(.vertical, AppDesign.Spacing.xxs)
                .background(
                    Capsule().fill(dark ? Color.white.opacity(0.18)
                                       : C.red.opacity(0.10))
                )
        }
    }

    private func premiumMeta(_ item: NewsItem, onDark: Bool) -> some View {
        HStack(spacing: 6) {
            Text(item.src)
                .fontWeight(.semibold)
            let t = timeText(item.at)
            if !t.isEmpty {
                Text("·")
                Text(t)
            }
            if item.hotValue > 0 {
                Text("·")
                Image(systemName: "flame.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(hotText(item.hotValue))
            }
        }
        .font(.system(size: 11.5))
        .textCase(.uppercase)
        .foregroundStyle(onDark ? Color.white.opacity(0.76) : Color.secondary)
        .lineLimit(1)
    }

    private var premiumBoard: some View {
        let rows = Array(items.enumerated())
        return VStack(spacing: 15) {
            premiumSectionTitle(Tr("实时热榜"), trailing: "\(items.count) " + Tr("条"))
            VStack(spacing: 0) {
                ForEach(rows, id: \.element.id) { row in
                    Button { open(row.element) } label: {
                        premiumBoardRow(row.element, index: row.offset)
                    }
                    .buttonStyle(.plain)
                    if row.offset < rows.count - 1 {
                        HairLine(inset: 54)
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous)
                    .stroke(C.hairline, lineWidth: 0.5)
            }
            premiumFooter
        }
        .padding(.horizontal, AppDesign.Spacing.md)
    }

    private func premiumBoardRow(_ item: NewsItem, index: Int) -> some View {
        let number = item.order > 0 ? item.order : index + 1
        return HStack(alignment: .top, spacing: 13) {
            Text("\(number)")
                .font(pfStyled(size: number <= 3 ? 18 : 16,
                              weight: number <= 3 ? .bold : .semibold))
                .monospacedDigit()
                .foregroundStyle(number <= 3 ? C.red : C.subLabel)
                .frame(width: 28, alignment: .leading)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.title)
                        .font(pfStyled(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if !item.tagText.isEmpty { tagChip(item.tagText) }
                }
                premiumMeta(item, onDark: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private var premiumFooter: some View {
        HStack {
            Spacer()
            Button { nextBatch() } label: {
                Label(Tr("换一批"), systemImage: "arrow.clockwise")
                    .font(pfStyled(size: 15, weight: .medium))
            }
            .buttonStyle(.bordered)
            .disabled(loading)
            Spacer()
        }
        .padding(.top, 2)
    }

    private func nextBatch() {
        let step = 20
        offset += step
        if total > 0, offset >= total { offset = 0 }
        Task { await load(tab) }
    }

    private var isBoard: Bool { tab == "weibo" || tab == "baidu" }

    @ViewBuilder private var content: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if items.isEmpty && loading {
                    ProgressView()
                        .tint(accent)
                        .padding(.top, compact ? 40 : 80)
                        .frame(maxWidth: .infinity)
                } else if items.isEmpty {
                    emptyView
                } else {
                    let rows = Array(items.enumerated())
                    ForEach(rows, id: \.element.id) { row in
                        Button { open(row.element) } label: {
                            cell(row.element, index: row.offset)
                        }
                        .buttonStyle(.plain)
                        HairLine(inset: 16)
                    }
                    footer
                }
            }
            .padding(.bottom, 28)
        }
        .background(C.cardBg)
        .refreshable { await load(tab) }
    }

    private var emptyView: some View {
        VStack(spacing: 14) {
            Text(failed ? Tr("稍后再看看") : Tr("正在加载…"))
                .font(pf(14))
                .foregroundColor(C.subLabel)
            Button { Task { await load(tab) } } label: {
                Text(Tr("重试"))
                    .font(pf(15, .medium))
                    .foregroundColor(accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, compact ? 50 : 90)
    }

    private var footer: some View {
        VStack(spacing: AppDesign.Spacing.md) {

            Button { nextBatch() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                    Text(Tr("换一批")).font(pf(14))
                }
                .foregroundColor(C.green)
                .padding(.horizontal, 18)
                .frame(height: 34)
                .background(Capsule().stroke(C.hairline, lineWidth: 0.5))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(loading)
            Text(Tr("已经到底了"))
                .font(pf(12))
                .foregroundColor(C.time)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppDesign.Spacing.lg)
    }

    @ViewBuilder private func cell(_ it: NewsItem, index: Int) -> some View {
        if isBoard {
            boardCell(it, index: index)
        } else if !it.cover.isEmpty {

            if index == 0 && !compact { heroCell(it) } else { thumbCell(it) }
        } else {
            textCell(it)
        }
    }

    private func heroCell(_ it: NewsItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(it.title)
                .font(pf(compact ? 16.5 : 17, .semibold))
                .foregroundColor(C.label)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            RemoteImage(path: it.cover, maxSide: 1400)
                .frame(height: compact ? 168 : 200)
                .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.micro, style: .continuous))
                .padding(.top, 10)
            meta(it)
                .padding(.top, 9)
        }
        .padding(.horizontal, AppDesign.Spacing.md)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func thumbCell(_ it: NewsItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(it.title)
                    .font(pf(compact ? 15.5 : 17))
                    .foregroundColor(C.label)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                meta(it)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RemoteImage(path: it.cover, maxSide: 800)
                .frame(width: compact ? 76 : 96, height: compact ? 57 : 72)
                .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.micro, style: .continuous))
        }
        .padding(.horizontal, compact ? 14 : 16)
        .padding(.vertical, compact ? 11 : 14)
    }

    private func textCell(_ it: NewsItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(it.title)
                .font(pf(compact ? 15.5 : 17))
                .foregroundColor(C.label)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let s = it.summary, !s.isEmpty {
                Text(s)
                    .font(pf(14))
                    .foregroundColor(C.subLabel)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            meta(it)
                .padding(.top, 2)
        }
        .padding(.horizontal, compact ? 14 : 16)
        .padding(.vertical, compact ? 11 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func boardCell(_ it: NewsItem, index: Int) -> some View {
        let no = it.order > 0 ? it.order : (index + 1)
        return HStack(alignment: .top, spacing: 12) {
            Text("\(no)")
                .font(AppDesign.Type.rowTitle)
                .foregroundColor(rankColor(no))
                .frame(width: 24, alignment: .leading)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 6) {
                    Text(it.title)
                        .font(pf(compact ? 16 : 17))
                        .foregroundColor(C.label)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !it.tagText.isEmpty { tagChip(it.tagText) }
                    Spacer(minLength: 0)
                }
                HStack(spacing: AppDesign.Spacing.xs) {
                    if it.hotValue > 0 {
                        Text(Tr("热度") + " " + hotText(it.hotValue))
                            .font(pf(12))
                            .foregroundColor(C.time)
                    }
                    Text(it.src)
                        .font(pf(12))
                        .foregroundColor(C.time)
                }
            }
        }
        .padding(.horizontal, AppDesign.Spacing.md)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func meta(_ it: NewsItem) -> some View {
        HStack(spacing: 6) {
            Text(it.src)
            let t = timeText(it.at)
            if !t.isEmpty {
                Text("·")
                Text(t)
            }
        }
        .font(pf(12))
        .foregroundColor(C.time)
        .lineLimit(1)
    }

    private func tagChip(_ text: String) -> some View {
        Text(text)
            .font(pf(10, .medium))
            .foregroundColor(C.red)
            .padding(.horizontal, AppDesign.Spacing.xxs)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.Radius.micro, style: .continuous)
                    .fill(C.red.opacity(0.12))
            )
    }

    private func rankColor(_ no: Int) -> Color {

        return no <= 3 ? C.label : C.time
    }

    private func select(_ id: String) {
        guard id != tab else { return }
        tab = id
        offset = 0
        compactHasMore = true
        compactLoadingMore = false
        items = []
        failed = false
        Task { await load(id) }
    }

    private func load(_ source: String) async {
        if loadingTab == source { return }
        loadingTab = source
        loading = true
        if compact {
            offset = 0
            compactHasMore = true
        }
        do {
            let feed = try await API.shared.news(source: source, limit: 20, offset: offset)
            guard source == tab else { loadingTab = ""; return }
            if onlyTabs == nil, !feed.tabs.isEmpty { channels = feed.tabs }
            if let t = feed.total, t > 0 { total = t }
            var seen = Set<String>()
            items = feed.items.filter { seen.insert($0.id).inserted }
            if compact {
                offset = feed.items.count
                compactHasMore = !feed.items.isEmpty
                    && (total <= 0 || offset < total)
            }
            failed = items.isEmpty
        } catch {
            guard source == tab else { loadingTab = ""; return }
            if items.isEmpty { failed = true }
        }
        loading = false
        loadingTab = ""
    }

    private func loadCompactMore() async {
        guard compact, !loading, !compactLoadingMore, compactHasMore else { return }
        compactLoadingMore = true
        defer { compactLoadingMore = false }
        let source = tab
        do {
            let feed = try await API.shared.news(source: source, limit: 20, offset: offset)
            guard source == tab else { return }
            var known = Set(items.map(\.id))
            let next = feed.items.filter { known.insert($0.id).inserted }
            items.append(contentsOf: next)
            offset += feed.items.count
            if let t = feed.total, t > 0 { total = t }
            compactHasMore = !feed.items.isEmpty
                && (total <= 0 || offset < total)
        } catch {
            compactHasMore = false
        }
    }

    private func open(_ it: NewsItem) {
        guard !it.link.isEmpty, let u = URL(string: it.link) else { return }
        web = WebURL(url: u)
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd"
        return f
    }()

    private func timeText(_ ms: Double) -> String {
        guard ms > 0 else { return "" }
        let d = Date(timeIntervalSince1970: ms / 1000)
        let mins = Int(Date().timeIntervalSince(d) / 60)
        if mins < 0 { return "" }
        if mins < 1 { return Tr("刚刚") }
        if mins < 60 { return "\(mins)\(Tr("分钟前"))" }
        if mins < 60 * 24 { return "\(mins / 60)\(Tr("小时前"))" }
        if mins < 60 * 24 * 2 { return Tr("昨天") }
        return NewsFeedView.dayFmt.string(from: d)
    }

    private func hotText(_ v: Double) -> String {
        if v >= 10000 {
            let w = v / 10000
            return String(format: "%.1f万", w)
        }
        return String(format: "%.0f", v)
    }
}

struct NewsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var refreshToken = 0
    @State private var official: API.OfficialAccount?
    @State private var editingOfficial: API.OfficialAccount?

    var modal: Bool = false

    var body: some View {
        NewsFeedView(refreshToken: refreshToken)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle((official?.name.isEmpty == false) ? (official?.name ?? Tr("时刻新闻")) : Tr("时刻新闻"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(uiColor: .systemGroupedBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            if modal {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                    }
                    .accessibilityLabel(Tr("返回"))
                }
            }
            if app.me?.ops == true {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { refreshToken += 1 } label: {
                            Label(Tr("刷新"), systemImage: "arrow.clockwise")
                        }
                        if official != nil {
                            Button {
                                editingOfficial = official
                            } label: {
                                Label(Tr("管理时刻新闻"), systemImage: "square.and.pencil")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .accessibilityLabel(Tr("更多"))
                }
            }
        }
        .task {
            guard app.me?.ops == true else { return }
            let list = (try? await API.shared.officialAccounts()) ?? []
            official = newsOfficial(in: list)
        }
        .sheet(item: $editingOfficial) { item in
            OfficialEditSheet(item: item) {
                let list = (try? await API.shared.officialAccounts()) ?? []
                official = newsOfficial(in: list)
            }
        }
        .hidesTabBar()
    }

    private func newsOfficial(in list: [API.OfficialAccount]) -> API.OfficialAccount? {
        for item in list {
            if item.key.lowercased().contains("news") {
                return item
            }
            if item.name == "星联世界" || item.name == "时刻新闻" {
                return item
            }
        }
        return nil
    }
}
