import SwiftUI
import AVKit
import PhotosUI
import UIKit

struct FeedAuthor: Decodable, Hashable {
    var id: String?
    var name: String?
    var avatar: String?
}

struct FeedItem: Decodable, Identifiable, Hashable {
    var id: String
    var video: String?

    var hls: String?
    var cover: String?

    var playPath: String {
        if let h = hls, !h.isEmpty { return h }
        return video ?? ""
    }
    var desc: String?
    var music: String?
    var tag: String?

    var ep: String?
    var epTotal: Int?
    var series: String?
    var seriesName: String?
    var favorited: Bool?
    var favorites: Int?
    var author: FeedAuthor?
    var createdAt: String?
    var likes: Int?
    var liked: Bool?

    var followed: Bool?
    var comments: Int?
    var shares: Int?
    var mine: Bool?
    var visibility: String?
}

struct ChannelsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var embedded = false
    var startingItems: [FeedItem]? = nil
    var startingItemID: String? = nil

    @State private var items: [FeedItem] = []

    @State private var showBigPlayer = false
    @State private var index = 0

    @State private var tab = 2
    @State private var drag: CGFloat = 0
    @State private var loading = true
    @State private var commentFor: FeedItem?
    @State private var commentsExpanded = false

    @State private var shareItem: FeedItem?
    @State private var forwardItem: FeedItem?
    @State private var commentText = ""
    @State private var comments: [FeedCommentItem] = []
    @State private var pickOpen = false
    @State private var picked: PhotosPickerItem?
    @State private var uploading = false

    @State private var uploadProgress: Double = 0
    @State private var uploadStage = ""

    @State private var pendingCover: UIImage?
    @State private var showPublish = false
    @State private var publishDesc = ""
    @State private var publishMusic = ""
    @State private var publishVisibility = "public"
    @State private var pendingVideoPath = ""
    @State private var pendingCoverPath = ""
    @State private var publishError = ""
    @State private var publishing = false
    @State private var coverPickOpen = false
    @State private var coverPicked: PhotosPickerItem?
    @State private var uploadJobID = UUID()
    @State private var uploadMB: Double = 0
    @State private var trim = 0
    @State private var style = FeedStyle()
    @State private var flags = FeedFlags()
    @State private var loadingMore = false
    @State private var episodeFor: FeedItem?
    @State private var seriesEpisodes: [FeedItem] = []

    @State private var showBili = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                if loading && items.isEmpty {
                    ProgressView().tint(.white)
                } else if items.isEmpty {
                    Text(Tr("视频号还没有内容\n去后台 data/feed.json 加，或者点右上角 ＋ 发一条"))
                        .font(pf(14)).foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                } else {

                    ForEach(visible, id: \.item.id) { row in
                        FeedCell(item: row.item,
                                 active: row.offset == 0,
                                 preload: row.offset == 1,
                                 style: style,
                                 flags: flags,
                                 onLike: { toggleLike(row.item) },
                    onComment: {
                        commentFor = row.item
                        commentsExpanded = false
                        commentText = ""
                        comments = []
                    },
                                 onShare: { share(row.item) },
                                 onFollow: { follow(row.item) },
                                 onDelete: { remove(row.item) },
                                 onPickEpisode: { episodeFor = row.item; seriesEpisodes = [] },
                                 onFavorite: { toggleFavorite(row.item) },
                                 videoScale: commentFor?.id == row.item.id
                                    ? (commentsExpanded ? 0.56 : 0.72)
                                    : 1)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .offset(y: CGFloat(row.offset) * geo.size.height + drag)
                    }
                }
                topBar
            }
            .allowsHitTesting(commentFor == nil)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { v in
                        guard !items.isEmpty else { return }
                        drag = v.translation.height
                    }
                    .onEnded { v in
                        guard !items.isEmpty else { return }
                        let h = geo.size.height
                        let far = abs(v.translation.height) > h * 0.22
                        let fast = abs(v.predictedEndTranslation.height) > h * 0.45
                        if (far || fast), v.translation.height < 0, index < items.count - 1 {
                            withAnimation(.easeOut(duration: 0.22)) { drag = -h }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { index += 1; drag = 0 }
                        } else if (far || fast), v.translation.height > 0, index > 0 {
                            withAnimation(.easeOut(duration: 0.22)) { drag = h }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { index -= 1; drag = 0 }
                        } else if (far || fast), v.translation.height < 0, index >= items.count - 1 {

                            withAnimation(.easeOut(duration: 0.22)) { drag = -h }
                            Task {
                                await loadMore()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    if index < items.count - 1 { index += 1 }
                                    drag = 0
                                }
                            }
                        } else {
                            withAnimation(.easeOut(duration: 0.22)) { drag = 0 }
                        }
                    }
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar(!embedded)
        .swipeBack(!embedded) { dismiss() }

        .fullScreenCover(isPresented: $showBili) {
            NavigationStack {
                VStack(spacing: 0) {
                    ZStack {
                        Text(Tr("B站热门")).font(pf(17, .semibold)).foregroundColor(C.label)
                        HStack(spacing: 0) {
                            Button { showBili = false } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 19, weight: .medium))
                                    .foregroundColor(C.label)
                                    .frame(width: 44, height: L.navH)
                            }
                            .buttonStyle(.plain)
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(height: L.navH)
                    .background(C.navBg)
                    .overlay(alignment: .bottom) { HairLine() }
                    NewsFeedView(compact: false,
                                 initialSource: "bili",
                                 onlyTabs: [NewsChannel(id: "bili", label: "B站热门", desc: "哔哩哔哩热门榜")])
                }
                .background(C.cardBg.ignoresSafeArea())
            }
        }

        .fullScreenCover(isPresented: $showBigPlayer) {
            FeedPlayerView(items: items, start: 0).environmentObject(app)
        }
        .overlay(alignment: .bottom) {
            if let item = commentFor {
                commentOverlay(item)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(80)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.88),
                   value: commentFor?.id)
        .animation(.spring(response: 0.30, dampingFraction: 0.90),
                   value: commentsExpanded)

        .sheet(item: $shareItem) { item in
            VideoShareSheet(
                item: item,
                onForward: { forwardItem = item },
                onToMoments: {
                    UIPasteboard.general.string = item.video ?? ""
                    app.show(Tr("链接已复制，去「发现 → 朋友圈」粘贴就能发"))
                },
                onFavorite: {
                    Task {
                        if let r = try? await API.shared.feedFavorite(item.id) {
                            app.show((r.favorited ? Tr("已收藏") : Tr("已取消收藏")))
                            await load()
                        }
                    }
                },
                onSaveLocal: {
                    UIPasteboard.general.string = item.video ?? ""
                    app.show(Tr("视频链接已复制；保存到相册会占内存，先在聊天里发给自己也能存"))
                },
                onHide: {
                    app.show(Tr("已经减少这类视频的推荐"))
                }
            )
            .environmentObject(app)
        }
        .sheet(item: $forwardItem) { item in
            VideoForwardPicker(link: item.video ?? "")
                .environmentObject(app)
        }
        .sheet(item: $episodeFor) { item in
            episodeSheet(item)
        }
        .fullScreenCover(isPresented: $showPublish) {
            publishEditor
        }
        .photosPicker(isPresented: $pickOpen, selection: $picked, matching: .videos)
        .onChange(of: picked) { v in Task { await uploadPicked(v) } }
        .photosPicker(isPresented: $coverPickOpen, selection: $coverPicked, matching: .images)
        .onChange(of: coverPicked) { item in
            Task {
                guard let item,
                      let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                pendingCover = image
                pendingCoverPath = ""
                coverPicked = nil
            }
        }
        .task {
            await load()
            PlayerPool.shared.focus(items: items, index: index)
        }

        .onChange(of: index) { i in
            PlayerPool.shared.focus(items: items, index: i)
            if i >= items.count - 2 { Task { await loadMore() } }
        }

        .onAppear {
            let s = AVAudioSession.sharedInstance()
            try? s.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try? s.setActive(true)
        }
        .onDisappear {
            VideoKernelTelemetry.shared.finishAll()
            PlayerPool.shared.suspend()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private var topBar: some View {
        VStack {
            HStack(spacing: 4) {
                if embedded {
                    Color.clear
                        .frame(width: 44, height: L.navH)
                } else {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: L.navH)
                            .background(Color.black.opacity(0.16), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Tr("返回"))
                }

                Spacer(minLength: 2)

                if startingItems == nil {
                    HStack(spacing: 24) {
                        ForEach(Array([UIConfig.text("feedTab0", "关注"),
                                       UIConfig.text("feedTab1", "朋友"),
                                       UIConfig.text("feedTab2", "推荐")].enumerated()), id: \.offset) { i, name in
                            Button {
                                guard tab != i else { return }
                                tab = i
                                index = 0
                                items = []
                                loading = true
                                Task { await load() }
                            } label: {
                                VStack(spacing: 5) {
                                    Text(Tr(name))
                                        .font(pf(tab == i ? 17 : 16, tab == i ? .semibold : .regular))
                                        .foregroundColor(tab == i ? .white : Color.white.opacity(0.58))
                                    Capsule()
                                        .fill(tab == i ? Color.white : Color.clear)
                                        .frame(width: 18, height: 2.5)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Text(Tr("我的作品"))
                        .font(pf(17, .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                Spacer(minLength: 2)

                Menu {
                    Button {
                        showBigPlayer = true
                    } label: {
                        Label(Tr("大屏播放"), systemImage: "rectangle.inset.filled")
                    }
                    Button {
                        showBili = true
                    } label: {
                        Label(Tr("B站热门"), systemImage: "play.square.stack")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 42, height: L.navH)
                        .background(Color.black.opacity(0.16), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Tr("更多"))

                if flags.allowPublish != false, startingItems == nil {
                    Button { pickOpen = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 42, height: L.navH)
                            .background(Color.black.opacity(0.16), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Tr("发布视频"))
                }
            }
            .padding(.horizontal, 6)
            Spacer()
        }
    }

    private struct Row { let item: FeedItem; let offset: Int }
    private var visible: [Row] {
        var out: [Row] = []
        for o in -1...1 {
            let i = index + o
            if i >= 0 && i < items.count { out.append(Row(item: items[i], offset: o)) }
        }
        return out
    }

    private func load() async {
        if let startingItems, !startingItems.isEmpty {
            items = startingItems
            if let startingItemID,
               let start = startingItems.firstIndex(where: { $0.id == startingItemID }) {
                index = start
            } else {
                index = 0
            }
            loading = false
            return
        }
        if let r = try? await API.shared.feed(tab: ["follow", "friends", "recommend"][tab]) {
            items = r.items
            style = r.style
            flags = r.flags
        }
        loading = false
    }

    private func loadMore() async {
        guard startingItems == nil else { return }
        if loadingMore { return }
        loadingMore = true
        defer { loadingMore = false }
        guard let r = try? await API.shared.feed(tab: ["follow", "friends", "recommend"][tab]) else { return }
        style = r.style
        flags = r.flags
        let known = Set(items.map { $0.id })
        let add = r.items.filter { !known.contains($0.id) }
        if add.isEmpty {
            items.append(contentsOf: r.items)
        } else {
            items.append(contentsOf: add)
        }
    }

    private func toggleFavorite(_ item: FeedItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        Task {
            if let r = try? await API.shared.feedFavorite(item.id) {
                items[i].favorited = r.favorited
                items[i].favorites = r.favorites
            }
        }
    }

    private func toggleLike(_ item: FeedItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        Task {
            if let r = try? await API.shared.feedLike(item.id) {
                items[i].liked = r.liked
                items[i].likes = r.likes
            }
        }
    }

    private func share(_ item: FeedItem) {
        shareItem = item
    }

    private func follow(_ item: FeedItem) {
        guard let uid = item.author?.id, !uid.isEmpty else { return }
        Task {

            let now = !(item.followed == true)
            let ok = await API.shared.feedFollow(userId: uid, follow: now)
            if ok {
                app.show(now ? Tr("已关注") : Tr("已取消关注"))
                await load()
            } else {
                app.show(Tr("关注失败，稍后再试"))
            }
        }
    }

    private func remove(_ item: FeedItem) {
        Task {
            await API.shared.feedDelete(item.id)
            await load()
            if index >= items.count { index = max(0, items.count - 1) }
        }
    }

    private func sendComment(_ item: FeedItem) {
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        commentText = ""
        Task {
            if let n = try? await API.shared.feedComment(item.id, text: text),
               let i = items.firstIndex(where: { $0.id == item.id }) {
                items[i].comments = n
            }
            await loadComments(item)
            app.show(Tr("评论成功"))
        }
    }

    private func loadComments(_ item: FeedItem) async {
        comments = (try? await API.shared.feedComments(item.id)) ?? []
    }

    private func episodeSheet(_ item: FeedItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.seriesName?.isEmpty == false ? (item.seriesName ?? "") : Tr("选集"))
                .font(pf(16, .semibold))
                .padding(.top, 16)
                .padding(.horizontal, 18)
            Text(Tr("共\(item.epTotal ?? seriesEpisodes.count)集"))
                .font(pf(12.5))
                .foregroundColor(.secondary)
                .padding(.horizontal, 18)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(seriesEpisodes) { ep in
                        Button {
                            jumpToEpisode(ep)
                            episodeFor = nil
                        } label: {
                            HStack(spacing: 10) {
                                Text(ep.ep ?? "")
                                    .font(pf(15, .medium))
                                    .foregroundColor(ep.id == item.id ? C.green : .primary)
                                Text(String((ep.desc ?? "").prefix(18)))
                                    .font(pf(13))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                if ep.id == item.id {
                                    Text(Tr("正在播放")).font(pf(12)).foregroundColor(C.green)
                                }
                            }
                            .padding(.vertical, 11)
                            .padding(.horizontal, 14)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                    if seriesEpisodes.isEmpty {
                        ProgressView().padding(.top, 20)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            guard let sid = item.series, !sid.isEmpty else { return }
            if let r = try? await API.shared.feedSeries(sid) { seriesEpisodes = r.items }
        }
    }

    private func jumpToEpisode(_ ep: FeedItem) {
        if let i = items.firstIndex(where: { $0.id == ep.id }) {
            index = i
        } else {
            let at = min(items.count, index + 1)
            items.insert(ep, at: at)
            index = at
        }
    }

    private func commentOverlay(_ item: FeedItem) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.20)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { closeComments() }

                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 38, height: 4)
                        .padding(.top, 8)

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(listCommentCount)
                                .font(pf(16, .semibold))
                                .foregroundColor(.white)
                            Text(item.desc ?? "")
                                .font(pf(12.5))
                                .foregroundColor(.white.opacity(0.56))
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                commentsExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: commentsExpanded
                                  ? "arrow.down.right.and.arrow.up.left"
                                  : "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.10), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(commentsExpanded ? Tr("收评论") : Tr("展开评论"))
                        Button { closeComments() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white.opacity(0.86))
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Tr("关闭评论"))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 9)
                    .padding(.bottom, 10)

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 0.5)

                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if comments.isEmpty {
                                Text(Tr("还没有评论，来说第一句"))
                                    .font(pf(14))
                                    .foregroundColor(.white.opacity(0.52))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 28)
                            }
                            ForEach(comments) { comment in
                                HStack(alignment: .top, spacing: 11) {
                                    Avatar(path: comment.avatar ?? "",
                                           size: 36,
                                           radius: 18,
                                           circle: true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(comment.name ?? Tr("用户"))
                                            .font(pf(13, .medium))
                                            .foregroundColor(.white.opacity(0.56))
                                        Text(comment.text ?? "")
                                            .font(pf(15))
                                            .foregroundColor(.white.opacity(0.94))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(TimeFmt.ago(comment.at))
                                            .font(pf(11))
                                            .foregroundColor(.white.opacity(0.35))
                                    }
                                    Image(systemName: "heart")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white.opacity(0.42))
                                        .padding(.top, 3)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                Rectangle()
                                    .fill(Color.white.opacity(0.055))
                                    .frame(height: 0.5)
                                    .padding(.leading, 63)
                            }
                        }
                        .padding(.bottom, 10)
                    }
                    .scrollDismissesKeyboard(.interactively)

                    HStack(spacing: 9) {
                        TextField(Tr("说点什么…"), text: $commentText)
                            .font(pf(15))
                            .foregroundColor(.white)
                            .padding(.horizontal, 13)
                            .frame(height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color.white.opacity(0.10))
                            )
                        Button { sendComment(item) } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Color(hex: 0xFE2C55)))
                        }
                        .buttonStyle(.plain)
                        .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.42 : 1)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 9)
                    .padding(.bottom, max(10, L.safeBottom + 4))
                    .background(.ultraThinMaterial)
                }
                .frame(height: commentsExpanded ? geo.size.height * 0.86 : geo.size.height * 0.62)
                .background(Color.black.opacity(0.96))
                .clipShape(TopRounded(radius: 24))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 0.5)
                }
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in
                            if value.translation.height > 70 {
                                if commentsExpanded {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                        commentsExpanded = false
                                    }
                                } else {
                                    closeComments()
                                }
                            } else if value.translation.height < -70 {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                    commentsExpanded = true
                                }
                            }
                        }
                )
            }
        }
        .preferredColorScheme(.dark)
        .task { await loadComments(item) }
    }

    private var listCommentCount: String {
        comments.isEmpty ? Tr("评论") : "\(comments.count) \(Tr("条评论"))"
    }

    private func closeComments() {
        withAnimation(.easeOut(duration: 0.20)) {
            commentFor = nil
            commentsExpanded = false
            commentText = ""
        }
    }

    private var publishEditor: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    publishHeader(topInset: max(geo.safeAreaInsets.top, L.safeTop))

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 14) {
                            publishPreview(height: min(470, max(330, geo.size.height * 0.46)))
                            publishDescriptionCard
                            publishSettingsCard

                            if uploading || !uploadStage.isEmpty {
                                publishUploadCard
                            }

                            if !publishError.isEmpty {
                                HStack(alignment: .top, spacing: 9) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundColor(Color(hex: 0xFF4D4F))
                                    Text(publishError)
                                        .font(pf(12.5))
                                        .foregroundColor(Color.white.opacity(0.70))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(12)
                                .background(Color(hex: 0xFF4D4F).opacity(0.10),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            Text(Tr("发布后将自动转码并生成清晰封面，稍后即可在作品页查看。"))
                                .font(pf(11.5))
                                .foregroundColor(Color.white.opacity(0.34))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 2)
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 6)
                        .padding(.bottom, max(24, L.safeBottom + 18))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(uploading || publishing)
    }

    private func publishHeader(topInset: CGFloat) -> some View {
        HStack(spacing: 12) {
            Button {
                cancelPublish()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("取消发布"))

            Spacer(minLength: 0)

            Text(Tr("发布作品"))
                .font(pf(17, .semibold))
                .foregroundColor(.white)

            Spacer(minLength: 0)

            Button {
                publish()
            } label: {
                HStack(spacing: 6) {
                    if publishing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Text(publishing ? Tr("发布中") : Tr("发布"))
                        .font(pf(14, .semibold))
                }
                .foregroundColor(canPublish ? .white : Color.white.opacity(0.34))
                .padding(.horizontal, 16)
                .frame(height: 34)
                .background(
                    Capsule(style: .continuous)
                        .fill(canPublish ? Color(hex: 0xFE2C55) : Color.white.opacity(0.10))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canPublish || publishing)
            .accessibilityLabel(Tr("发布作品"))
        }
        .padding(.horizontal, 14)
        .padding(.top, topInset + 4)
        .padding(.bottom, 8)
        .background(Color.black)
    }

    private func publishPreview(height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color(hex: 0x111214)

            if let cover = pendingCover {
                Image(uiImage: cover)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [Color(hex: 0x24252A), Color(hex: 0x08090B)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: uploading ? "arrow.triangle.2.circlepath" : "play.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(.white.opacity(0.58))
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.08), .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )

            if uploading {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.18), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: max(0.02, min(1, uploadProgress)))
                            .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(uploadProgress > 0.01
                             ? "\(Int(min(1, uploadProgress) * 100))%"
                             : "…")
                            .font(pfStyled(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 54, height: 54)

                    Text(uploadStage.isEmpty ? Tr("正在处理视频…") : uploadStage)
                        .font(pf(13, .medium))
                        .foregroundColor(.white.opacity(0.88))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.30))
            }

            VStack(alignment: .leading, spacing: 10) {
                if uploadMB > 0 {
                    Label(String(format: "%.1f MB", uploadMB), systemImage: "checkmark.circle.fill")
                        .font(pf(11.5, .medium))
                        .foregroundColor(.white.opacity(0.88))
                }

                HStack(spacing: 9) {
                    Label(publishMusic.isEmpty ? Tr("原声") : publishMusic,
                          systemImage: "music.note")
                        .font(pf(12, .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Color.black.opacity(0.44), in: Capsule())

                    Spacer(minLength: 8)

                    Button { coverPickOpen = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text(pendingCover == nil ? Tr("选择封面") : Tr("更换封面"))
                        }
                        .font(pf(12, .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(13)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
        }
    }

    private var publishDescriptionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Tr("作品描述"))
                    .font(pf(14.5, .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text("\(publishDesc.count)/120")
                    .font(pf(11))
                    .foregroundColor(Color.white.opacity(0.38))
            }

            ZStack(alignment: .topLeading) {
                if publishDesc.isEmpty {
                    Text(Tr("添加作品描述，让更多人了解这条作品…"))
                        .font(pf(14.5))
                        .foregroundColor(Color.white.opacity(0.36))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                }

                TextEditor(text: $publishDesc)
                    .font(pf(14.5))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .onChange(of: publishDesc) { value in
                        if value.count > 120 {
                            publishDesc = String(value.prefix(120))
                        }
                    }
            }
            .frame(height: 92)

            HStack(spacing: 8) {
                publishQuickToken("@")
                publishQuickToken("#")
                Button {
                    publishDesc += "😊"
                } label: {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.78))
                        .frame(width: 30, height: 28)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                Text(Tr("添加话题和好友，更容易被发现"))
                    .font(pf(10.5))
                    .foregroundColor(Color.white.opacity(0.30))
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.065),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.7)
        }
    }

    private var publishSettingsCard: some View {
        VStack(spacing: 0) {
            publishSettingRow(icon: "music.note", title: Tr("添加音乐")) {
                TextField(Tr("选填，例如：原声"), text: $publishMusic)
                    .font(pf(13.5))
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(Color.white.opacity(0.58))
                    .frame(maxWidth: 170)
            }

            publishSettingDivider

            publishSettingRow(icon: "eye", title: Tr("谁可以看"),
                              detail: publishAudienceTitle) {
                Menu {
                    Button(Tr("公开")) { publishVisibility = "public" }
                    Button(Tr("仅朋友")) { publishVisibility = "friends" }
                    Button(Tr("仅自己")) { publishVisibility = "private" }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.32))
                }
            }

            publishSettingDivider

            Button { coverPickOpen = true } label: {
                publishSettingRow(icon: "photo", title: Tr("选择封面"),
                                  detail: pendingCover == nil ? Tr("视频首帧") : Tr("已选择")) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.32))
                }
            }
            .buttonStyle(.plain)

            if flags.allowTrim != false {
                publishSettingDivider

                publishSettingRow(icon: "wand.and.stars", title: Tr("清除水印"),
                                  detail: trimTitle) {
                    Menu {
                        Button(Tr("不处理")) { trim = 0 }
                        Button(Tr("底部 10%")) { trim = 1 }
                        Button(Tr("底部 14%")) { trim = 2 }
                        Button(Tr("右侧 12%")) { trim = 3 }
                        Button(Tr("右下角")) { trim = 4 }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.32))
                    }
                }
            }

            publishSettingDivider

            publishSettingRow(icon: "bolt.hd.fill", title: Tr("画质"),
                              detail: Tr("高清 · 自动转码")) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(hex: 0x25F4EE))
            }
        }
        .background(Color.white.opacity(0.065),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.7)
        }
    }

    private var publishUploadCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(uploadStage.isEmpty ? Tr("视频已就绪") : uploadStage)
                    .font(pf(12.5, .medium))
                    .foregroundColor(.white.opacity(0.78))
                Spacer()
                if uploadMB > 0 {
                    Text(String(format: "%.1f MB", uploadMB))
                        .font(pf(11))
                        .foregroundColor(.white.opacity(0.38))
                }
            }

            if uploading {
                ProgressView(value: max(0.02, min(1, uploadProgress)))
                    .tint(Color(hex: 0x25F4EE))
            } else {
                Label(Tr("可以发布"), systemImage: "checkmark.seal.fill")
                    .font(pf(12))
                    .foregroundColor(Color(hex: 0x25F4EE))
            }
        }
        .padding(13)
        .background(Color.white.opacity(0.065),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func publishQuickToken(_ token: String) -> some View {
        Button {
            publishDesc += token
        } label: {
            Text(token)
                .font(pf(16, .semibold))
                .foregroundColor(Color.white.opacity(0.82))
                .frame(width: 30, height: 28)
                .background(Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var publishSettingDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 0.6)
            .padding(.leading, 48)
    }

    private var publishAudienceTitle: String {
        switch publishVisibility {
        case "friends": return Tr("仅朋友")
        case "private": return Tr("仅自己")
        default: return Tr("公开")
        }
    }

    private var canPublish: Bool {
        !pendingVideoPath.isEmpty && !uploading
    }

    private func publishSettingRow<Accessory: View>(
        icon: String,
        title: String,
        detail: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.82))
                .frame(width: 22)
            Text(title)
                .font(pf(15))
                .foregroundColor(.white)
            Spacer(minLength: 10)
            if let detail {
                Text(detail)
                    .font(pf(13.5))
                    .foregroundColor(Color.white.opacity(0.40))
                    .lineLimit(1)
            }
            accessory()
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private var trimTitle: String {
        switch trim {
        case 1: return Tr("底部 10%")
        case 2: return Tr("底部 14%")
        case 3: return Tr("右侧 12%")
        case 4: return Tr("右下角")
        default: return Tr("不处理")
        }
    }

    private func uploadPicked(_ v: PhotosPickerItem?) async {
        guard let v = v else { return }
        let job = UUID()
        uploadJobID = job
        pendingVideoPath = ""
        pendingCoverPath = ""
        pendingCover = nil
        publishError = ""
        publishVisibility = "public"
        uploadMB = 0
        uploading = true
        showPublish = true
        uploadProgress = 0
        uploadStage = Tr("准备中…")
        defer {
            picked = nil
            if uploadJobID == job {
                uploading = false
                uploadStage = ""
            }
        }
        do {
            guard let data = try await v.loadTransferable(type: Data.self), !data.isEmpty else {
                if uploadJobID == job { publishError = Tr("读不到这个视频，请重新选择") }
                return
            }
            guard uploadJobID == job else { return }

            let raw = FileManager.default.temporaryDirectory.appendingPathComponent("feed-raw-\(UUID().uuidString).mov")
            try data.write(to: raw)

            if pendingCover == nil, let img = await MediaTool.firstFrame(raw) {
                if uploadJobID == job { pendingCover = img }
            }
            let uploadData: Data
            let mb = Double(data.count) / 1024 / 1024
            if mb <= 6 {
                uploadData = data
            } else {
                uploadStage = Tr("压缩中…")
                let preset: String = mb > 18 ? "720p" : "1080p"
                let small = await Self.compress(raw, preset: preset)
                if let small = small, !small.isEmpty, small.count < data.count {
                    uploadData = small
                } else {
                    uploadData = data
                }
            }
            try? FileManager.default.removeItem(at: raw)

            uploadStage = Tr("上传中…")
            let upFile = FileManager.default.temporaryDirectory.appendingPathComponent("feed-up-\(UUID().uuidString).mp4")
            try uploadData.write(to: upFile)
            uploadProgress = 0
            let url = try await API.shared.uploadBinaryFile(upFile, mime: "video/mp4", skipTranscode: true) { p in
                DispatchQueue.main.async {
                    if uploadJobID == job { uploadProgress = p }
                }
            }
            try? FileManager.default.removeItem(at: upFile)
            guard uploadJobID == job else { return }
            pendingVideoPath = url
            uploadMB = Double(uploadData.count) / 1024 / 1024
        } catch {
            if uploadJobID == job {
                publishError = (error as? APIError)?.errorDescription
                    ?? Tr("视频上传失败，请检查网络后重新选择")
            }
        }
    }

    nonisolated static func compress(_ url: URL, preset: String = "1080p") async -> Data? {
        let asset = AVURLAsset(url: url)

        let exportName = (preset == "720p") ? AVAssetExportPreset1280x720 : AVAssetExportPreset1920x1080
        guard let export = AVAssetExportSession(asset: asset, presetName: exportName) else { return nil }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("feed-out-\(UUID().uuidString).mp4")
        export.outputURL = out
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { c.resume() }
        }
        guard export.status == .completed else { return nil }
        let d = try? Data(contentsOf: out)
        try? FileManager.default.removeItem(at: out)
        return d
    }

    private func publish() {
        guard canPublish, !publishing else { return }
        let desc = publishDesc.trimmingCharacters(in: .whitespacesAndNewlines)
        let music = publishMusic.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibility = publishVisibility
        let cover = pendingCover
        let baseVideo = pendingVideoPath
        let crop = trim
        publishing = true
        publishError = ""
        Task {
            do {
                var video = baseVideo
                if crop > 0 {
                    let area: (top: Double, bottom: Double, left: Double, right: Double)
                    switch crop {
                    case 1: area = (0, 0.10, 0, 0)
                    case 2: area = (0, 0.14, 0, 0)
                    case 3: area = (0, 0, 0, 0.12)
                    default: area = (0, 0.12, 0, 0.10)
                    }
                    if let trimmed = try? await API.shared.feedTrim(video, top: area.top, bottom: area.bottom,
                                                                     left: area.left, right: area.right) {
                        video = trimmed
                    }
                }
                var coverPath = pendingCoverPath
                if coverPath.isEmpty, let cover {
                    coverPath = (try? await API.shared.uploadCover(image: cover)) ?? ""
                }
                _ = try await API.shared.feedPublish(
                    video: video,
                    desc: desc,
                    music: music,
                    cover: coverPath,
                    visibility: visibility
                )
                app.show(Tr("发表成功"))
                resetPublishDraft(close: true)
                index = 0
                await load()
            } catch {
                publishError = (error as? APIError)?.errorDescription
                    ?? Tr("发表失败，请检查网络后重试")
            }
            publishing = false
        }
    }

    private func cancelPublish() {
        uploadJobID = UUID()
        uploading = false
        publishing = false
        resetPublishDraft(close: true)
    }

    private func resetPublishDraft(close: Bool) {
        publishDesc = ""
        publishMusic = ""
        pendingCover = nil
        pendingCoverPath = ""
        pendingVideoPath = ""
        publishVisibility = "public"
        publishError = ""
        uploadProgress = 0
        uploadStage = ""
        uploadMB = 0
        trim = 0
        if close { showPublish = false }
    }
}

struct FeedCell: View {
    let item: FeedItem
    let active: Bool
    var preload = false
    var style = FeedStyle()
    var flags = FeedFlags()
    var onLike: () -> Void
    var onComment: () -> Void
    var onShare: () -> Void
    var onFollow: () -> Void
    var onDelete: () -> Void
    var onPickEpisode: () -> Void = {}
    var onFavorite: () -> Void = {}
    var videoScale: CGFloat = 1

    @ObservedObject private var playerPool = PlayerPool.shared
    @State private var liked = false
    @State private var likes = 0
    @State private var favorited = false
    @State private var favorites = 0
    @State private var bounced = false
    @State private var progress: Double = 0
    @State private var durationSec: Double = 0
    @State private var timeObserver: Any?
    @State private var observedPlayer: AVPlayer?

    private var player: AVPlayer? { playerPool.player(for: item) }
    private var loadingVideo: Bool {
        !playerPool.isReady(item.id)
            && !playerPool.hasPlayed(item.id)
            && !playerPool.failed.contains(item.id)
    }
    private var seriesTitle: String {
        let name = (item.seriesName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name + (item.ep.map { " · " + $0 } ?? "")
        }
        return Tr("选集") + (item.ep.map { " · " + $0 } ?? "")
    }
    private var progressTime: String {
        guard durationSec.isFinite, durationSec > 0 else { return "" }
        let current = max(0, min(durationSec, durationSec * progress))
        return videoClock(current) + " / " + videoClock(durationSec)
    }

    private func videoClock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d",
                          total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var body: some View {
        ZStack {
            Color.black
            if !(item.cover ?? "").isEmpty {
                RemoteImage(path: item.cover ?? "")
                    .opacity(playerPool.hasPlayed(item.id) ? 0.001 : 1)
            }
            if let p = player {
                PlayerSurface(player: p)
            }
            if loadingVideo {
                ProgressView().tint(.white)
            }
            LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.65)],
                           startPoint: .top, endPoint: .bottom)

            VStack {
                Spacer()
                VStack(spacing: 7) {
                    HStack(spacing: 8) {
                        if (item.epTotal ?? 0) > 1 || !(item.seriesName ?? "").isEmpty {
                            Button { onPickEpisode() } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "rectangle.stack.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(seriesTitle)
                                        .font(pf(12, .semibold))
                                        .lineLimit(1)
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 9)
                                .frame(height: 25)
                                .background(Color.black.opacity(0.42), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                        Text(progressTime)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.82))
                            .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                    }
                    .padding(.horizontal, 16)

                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.22))
                            Rectangle().fill(Color.white)
                                .frame(width: max(0, min(1, progress)) * g.size.width)
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                            let r = max(0, min(1, v.location.x / max(1, g.size.width)))
                            progress = r
                            if durationSec > 0 {
                                player?.seek(to: CMTime(seconds: r * durationSec, preferredTimescale: 600),
                                             toleranceBefore: .zero, toleranceAfter: .zero)
                            }
                        })
                    }
                }
                .padding(.bottom, 2)
            }

            if flags.showRail != false {
                HStack(alignment: .bottom, spacing: 0) {
                    Spacer()
                    rightRail
                }
                .padding(.trailing, 12)
                .padding(.bottom, 110)
            }

            VStack(alignment: .leading, spacing: 8) {
                Spacer()
                Text("@\(item.author?.name ?? "用户")")
                    .font(pf(style.nameSize ?? 16, .semibold)).foregroundColor(.white)
                Text(item.desc ?? "")
                    .font(pf(style.descSize ?? 14)).foregroundColor(.white.opacity(0.95))
                    .lineLimit(3)
                HStack(spacing: 5) {
                    Image(systemName: "music.note").font(.system(size: 12))
                    Text(item.music?.isEmpty == false ? (item.music ?? "") : "原创声音")
                        .font(pf(style.musicSize ?? 12.5))
                }
                .foregroundColor(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, max(style.padBottom ?? 28, L.safeBottom + 46))
        }
        .scaleEffect(videoScale, anchor: .top)
        .offset(y: videoScale < 0.99 ? 10 : 0)

        .onAppear {
            if active { setup() }
            else if preload { _ = player }
        }
        .onDisappear { deactivate() }
        .onChange(of: active) { on in
            if on {
                setup()
                playerPool.play(item)
            } else {
                deactivate()
            }
        }
        .onChange(of: preload) { on in
            if on, !active { _ = player }
        }
    }

    private func deactivate() {
        VideoKernelTelemetry.shared.finish(item.id)
        if let obs = timeObserver, let p = observedPlayer { p.removeTimeObserver(obs) }
        timeObserver = nil
        observedPlayer = nil
        playerPool.pause(item)
        progress = 0
    }

    private var rightRail: some View {
        VStack(spacing: max(style.railGap ?? 18, 18)) {
            ZStack(alignment: .bottom) {
                Avatar(path: item.author?.avatar ?? "", size: style.avatar ?? 48,
                       radius: (style.avatar ?? 48) / 2, circle: true)
                    .overlay(Circle().stroke(Color.white.opacity(0.94), lineWidth: 1.4))
                    .shadow(color: .black.opacity(0.42), radius: 7, y: 3)
                Button {
                    VideoKernelTelemetry.shared.event("follow", itemId: item.id)
                    onFollow()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color(hex: 0xFE2C55)))
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.2))
                        .shadow(color: .black.opacity(0.34), radius: 4, y: 2)
                        .offset(y: 8)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 10)

            railAction(icon: "heart.fill", tint: liked ? Color(hex: 0xFF4D6D) : .white,
                       count: "\(likes)", active: liked, bounce: bounced) {
                liked.toggle()
                likes += liked ? 1 : -1
                bounced = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { bounced = false }
                VideoKernelTelemetry.shared.event(liked ? "like" : "unlike", itemId: item.id)
                onLike()
            }
            railAction(icon: "bubble.right.fill", tint: .white, count: "\(item.comments ?? 0)") {
                VideoKernelTelemetry.shared.event("comment", itemId: item.id)
                onComment()
            }

            railAction(icon: "star.fill", tint: favorited ? Color(hex: 0xFFC542) : .white,
                       count: "\(favorites)", active: favorited) {
                favorited.toggle()
                favorites += favorited ? 1 : -1
                VideoKernelTelemetry.shared.event(favorited ? "favorite" : "unfavorite",
                                                   itemId: item.id)
                onFavorite()
            }
            railAction(icon: "arrowshape.turn.up.right.fill", tint: .white, count: "\(item.shares ?? 0)") {
                VideoKernelTelemetry.shared.event("share", itemId: item.id)
                onShare()
            }
            if item.mine == true {
                railAction(icon: "trash.fill", tint: .white, count: Tr("删除"), action: onDelete)
            }
        }
    }

    private func railAction(icon: String, tint: Color, count: String, active: Bool = false,
                            bounce: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundColor(tint)
                    .shadow(color: .black.opacity(0.65), radius: 4, y: 2)
                    .scaleEffect(bounce ? 1.20 : 1)
                    .frame(width: 46, height: 34)
                    .overlay(alignment: .topTrailing) {
                        if active {
                            Circle()
                                .fill(Color.white.opacity(0.92))
                                .frame(width: 4, height: 4)
                                .offset(x: -3, y: 2)
                        }
                    }
                if !count.isEmpty {
                    Text(count)
                        .font(pf(12.5, .semibold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.72), radius: 3, y: 1)
                }
            }
            .frame(width: 54)
        }
        .buttonStyle(.plain)
    }

    private func setup() {
        if active {
            VideoKernelTelemetry.shared.begin(item.id)
        }
        liked = item.liked ?? false
        likes = item.likes ?? 0
        favorited = item.favorited ?? false
        favorites = item.favorites ?? 0
        guard let player else { return }
        observedPlayer = player
        installObservers(player)
        playerPool.play(item)
    }

    private func installObservers(_ p: AVPlayer) {
        if timeObserver != nil { return }
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { t in
            let d = p.currentItem?.duration.seconds ?? 0
            if d.isFinite, d > 0 {
                durationSec = d
                progress = min(1, max(0, t.seconds / d))
                VideoKernelTelemetry.shared.update(item.id,
                                                  progress: progress,
                                                  duration: d)
            }
        }
    }
}

struct FeedPlayerSheet: View {
    let item: FeedItem
    var all: [FeedItem] = []

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var loading = true
    @State private var liked = false
    @State private var likes = 0
    @State private var index = 0
    @State private var heartBurst = false

    private var list: [FeedItem] { all.isEmpty ? [item] : all }
    private var cur: FeedItem { list[min(index, list.count - 1)] }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let p = player { PlayerSurface(player: p) }
            if loading { ProgressView().tint(.white) }
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 8)
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("@\(cur.author?.name ?? "用户")")
                            .font(pf(15, .semibold)).foregroundColor(.white)
                        Text(cur.desc ?? "").font(pf(13.5)).foregroundColor(.white.opacity(0.95))
                            .lineLimit(3)
                        if !(cur.music ?? "").isEmpty {
                            Text("♪ \(cur.music ?? "")").font(pf(12)).foregroundColor(.white.opacity(0.8))
                        }
                    }
                    Spacer(minLength: 12)
                    Button {
                        let willLike = !liked
                        liked.toggle(); likes += liked ? 1 : -1
                        if willLike {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            heartBurst = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                heartBurst = false
                            }
                        }
                        Task { _ = try? await API.shared.feedLike(cur.id) }
                    } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 26))
                                    .foregroundColor(liked ? Color(hex: 0xFF4D6D) : .white)
                                if heartBurst { HeartBurst() }
                            }
                            Text("\(likes)").font(pf(12.5)).foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, max(20, L.safeBottom + 8))
            }

            if list.count > 1 {
                HStack {
                    Button { step(-1) } label: { chevron("chevron.left") }
                    Spacer()
                    Button { step(1) } label: { chevron("chevron.right") }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
            }
        }
        .onAppear {
            index = list.firstIndex(where: { $0.id == item.id }) ?? 0
            liked = cur.liked ?? false
            likes = cur.likes ?? 0
            heartBurst = false
            load(cur)
        }

        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private func chevron(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 22, weight: .semibold))
            .foregroundColor(.white.opacity(0.75))
            .frame(width: 44, height: 60)
    }

    private func step(_ d: Int) {
        let n = index + d
        guard n >= 0, n < list.count else { return }
        index = n
        liked = cur.liked ?? false
        likes = cur.likes ?? 0
        player?.pause()
        player = nil
        load(cur)
    }

    private func load(_ w: FeedItem) {

        let path = w.playPath
        guard let url = API.shared.assetURL(path) else { loading = false; return }
        loading = true
        let canFallback = !(w.video ?? "").isEmpty && (w.video ?? "") != path
        Task { @MainActor in
            func mount(_ playURL: URL, allowFallback: Bool, viaDownload: Bool = false) async {
                var realURL = playURL
                if viaDownload {

                    guard let local = await StreamPlay.download(playURL) else { loading = false; return }
                    realURL = local
                }
                let p = viaDownload ? AVPlayer(url: realURL) : (StreamPlay.player(realURL) ?? AVPlayer(url: realURL))
                p.actionAtItemEnd = .none

                p.automaticallyWaitsToMinimizeStalling = false
                p.currentItem?.preferredForwardBufferDuration = 1.5
                NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                       object: p.currentItem, queue: .main) { _ in
                    p.seek(to: .zero); p.play()
                }
                if let old = player, old !== p {
                    old.pause()
                    StreamPlay.cancel(old.currentItem)
                }
                player = p
                p.play()
                var moved = false
                for _ in 0..<(allowFallback ? 15 : 60) {
                    if let it = p.currentItem {
                        if it.status == .failed { break }
                        if it.status == .readyToPlay, CMTimeGetSeconds(p.currentTime()) > 0.05 {
                            moved = true
                            break
                        }
                    }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    if player !== p { return }
                }
                if player !== p { return }
                if moved { loading = false; return }
                if allowFallback, let v = w.video, !v.isEmpty, let u2 = API.shared.assetURL(v) {
                    CrashCatcher.note("视频号", "分片 3 秒没画面，改用整包 MP4（先下后播）id=\(w.id)")
                    await mount(u2, allowFallback: false, viaDownload: true)
                } else {
                    loading = false
                }
            }
            await mount(url, allowFallback: canFallback)
        }
    }
}

struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let v = PlayerView()
        v.backgroundColor = .black
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ v: PlayerView, context: Context) {
        v.playerLayer.player = player
    }

    static func dismantleUIView(_ uiView: PlayerView, coordinator: ()) {
        uiView.playerLayer.player = nil
    }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
