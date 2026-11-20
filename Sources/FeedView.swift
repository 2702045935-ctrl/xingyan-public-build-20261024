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
                    onComment: { commentFor = row.item; commentText = ""; comments = [] },
                                 onShare: { share(row.item) },
                                 onFollow: { follow(row.item) },
                                 onDelete: { remove(row.item) },
                                 onPickEpisode: { episodeFor = row.item; seriesEpisodes = [] },
                                 onFavorite: { toggleFavorite(row.item) })
                            .frame(width: geo.size.width, height: geo.size.height)
                            .offset(y: CGFloat(row.offset) * geo.size.height + drag)
                    }
                }
                topBar
            }
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
        .sheet(item: $commentFor) { item in
            commentSheet(item)
        }

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
        .task { await load() }

        .onChange(of: index) { i in
            if i >= items.count - 2 { Task { await loadMore() } }
        }

        .onAppear {
            let s = AVAudioSession.sharedInstance()
            try? s.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try? s.setActive(true)
        }
        .onDisappear {
            VideoKernelTelemetry.shared.finishAll()
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

    private func commentSheet(_ item: FeedItem) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Tr("评论"))
                        .font(pf(16, .semibold))
                        .foregroundColor(C.label)
                    Text(item.desc ?? "")
                        .font(pf(12.5))
                        .foregroundColor(C.subLabel)
                        .lineLimit(1)
                }
                Spacer()
                Button { commentFor = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(C.subLabel)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(C.searchBg))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 11)

            HairLine(inset: 0)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 13) {
                    if comments.isEmpty {
                        Text(Tr("还没有评论，来说第一句"))
                            .font(pf(14))
                            .foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 20)
                    }
                    ForEach(comments) { c in
                        HStack(alignment: .top, spacing: 10) {
                            Avatar(path: c.avatar ?? "用户", size: 34, radius: 17, circle: true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(c.name ?? Tr("用户"))
                                    .font(pf(12.5, .medium))
                                    .foregroundColor(C.subLabel)
                                Text(c.text ?? "")
                                    .font(pf(14.5))
                                    .foregroundColor(C.label)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
            }
            .frame(maxHeight: .infinity)

            HairLine(inset: 0)

            HStack(spacing: 9) {
                TextField("说点什么…", text: $commentText)
                    .font(pf(14.5))
                    .padding(.horizontal, 13)
                    .frame(height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .fill(C.searchBg)
                    )
                Button { sendComment(item) } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(C.green))
                }
                .buttonStyle(.plain)
                .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 9)
            .padding(.bottom, max(10, L.safeBottom + 4))
            .background(.ultraThinMaterial)
        }
        .background(C.cardBg)
        .presentationDetents([.fraction(0.64), .large])
        .presentationDragIndicator(.visible)
        .task { await loadComments(item) }
    }

    private var publishEditor: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    publishHeader

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

    private var publishHeader: some View {
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
        .padding(.top, 4)
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

    @State private var player: AVPlayer?
    @State private var loadingVideo = true
    @State private var liked = false
    @State private var likes = 0
    @State private var favorited = false
    @State private var favorites = 0
    @State private var bounced = false
    @State private var progress: Double = 0
    @State private var durationSec: Double = 0
    @State private var timeObserver: Any?

    var body: some View {
        ZStack {
            Color.black
            if !(item.cover ?? "").isEmpty {
                RemoteImage(path: item.cover ?? "").opacity(player == nil ? 1 : 0.001)
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
                .frame(height: 3)
            }

            if !(item.ep ?? "").isEmpty {
                VStack {
                    HStack(spacing: 8) {
                        Text(item.ep ?? "")
                            .font(pf(13, .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                        if (item.epTotal ?? 0) > 1 {
                            Button { onPickEpisode() } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "list.bullet").font(.system(size: 11, weight: .semibold))
                                    Text(Tr("选集")).font(pf(13, .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.black.opacity(0.45)))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
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
            .padding(.bottom, max(style.padBottom ?? 28, L.safeBottom + 10))
        }

        .onAppear {
            if active { setup() }
            else if preload { prewarm() }
        }
        .onDisappear { teardown() }
        .onChange(of: active) { on in
            if on {
                setup()
                player?.play()
            } else if preload {
                player?.pause()
            } else {
                teardown()
            }
        }
        .onChange(of: preload) { on in
            if on, !active {
                prewarm()
            } else if !on, !active {
                teardown()
            }
        }
    }

    private func teardown() {
        VideoKernelTelemetry.shared.finish(item.id)
        if let obs = timeObserver, let p = player { p.removeTimeObserver(obs) }
        timeObserver = nil
        player?.pause()
        player = nil
        loadingVideo = true
        progress = 0
    }

    private var rightRail: some View {
        VStack(spacing: max(style.railGap ?? 22, 22)) {
            ZStack(alignment: .bottom) {
                Avatar(path: item.author?.avatar ?? "", size: style.avatar ?? 46,
                       radius: (style.avatar ?? 46) / 2, circle: true)
                    .overlay(Circle().stroke(Color.white.opacity(0.92), lineWidth: 1.6))
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                Button {
                    VideoKernelTelemetry.shared.event("follow", itemId: item.id)
                    onFollow()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundColor(.white)
                        .frame(width: 21, height: 21)
                        .background(Circle().fill(LinearGradient(colors: [Color(hex: 0xFF6B6B), Color(hex: 0xFA5151)],
                                                                 startPoint: .top, endPoint: .bottom)))
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.2))
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        .offset(y: 10)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 12)

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
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().fill(Color.black.opacity(active ? 0.26 : 0.14)))
                        .overlay(Circle().stroke(Color.white.opacity(active ? 0.36 : 0.18), lineWidth: 0.9))
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                    Image(systemName: icon)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(tint)
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                }
                .scaleEffect(bounce ? 1.18 : 1)
                if !count.isEmpty {
                    Text(count)
                        .font(pf(12.5, .semibold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
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
        if let existing = player {
            if existing.currentItem?.status == .failed {
                teardown()
            } else {
                installObservers(existing)
                if active { existing.play() }
                verifyPrewarmed(existing)
                return
            }
        }

        let hls = item.playPath
        let mp4 = item.video ?? ""
        let path = hls.isEmpty ? mp4 : hls
        guard let url = API.shared.assetURL(path) else { return }
        loadingVideo = true
        CrashCatcher.note("视频号", "开始加载 id=\(item.id) 源=\(path)")
        let streaming = !hls.isEmpty && path == hls
        startPlayer(path: path, url: url,
                    canFallback: !mp4.isEmpty && mp4 != path,
                    viaDownload: !streaming)
    }

    private func prewarm() {
        guard !active, player == nil,
              let hls = item.hls, !hls.isEmpty,
              let url = API.shared.assetURL(hls) else { return }
        let prepared = StreamPlay.player(url) ?? AVPlayer(url: url)
        prepared.actionAtItemEnd = .none
        prepared.automaticallyWaitsToMinimizeStalling = false
        prepared.currentItem?.preferredForwardBufferDuration = 0.8
        prepared.pause()
        player = prepared
        loadingVideo = true
        CrashCatcher.note("视频号", "预取下一条 id=\(item.id) 源=\(hls)")
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
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                               object: p.currentItem, queue: .main) { _ in
            VideoKernelTelemetry.shared.complete(item.id)
            p.seek(to: .zero)
            p.play()
        }
    }

    private func verifyPrewarmed(_ p: AVPlayer) {
        guard active else { return }
        Task { @MainActor in
            for _ in 0..<15 {
                if player !== p || !active { return }
                if p.currentItem?.status == .failed { break }
                if CMTimeGetSeconds(p.currentTime()) > 0.05 {
                    loadingVideo = false
                    VideoKernelTelemetry.shared.event("first_frame", itemId: item.id)
                    return
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            guard player === p, active else { return }
            teardown()
            setup()
        }
    }

    private func startPlayer(path: String, url: URL, canFallback: Bool, viaDownload: Bool = false) {
        Task { @MainActor in

            var playURL = url
            if viaDownload {
                guard let local = await StreamPlay.download(url) else {

                    if canFallback, let h = item.hls, !h.isEmpty,
                       let u2 = API.shared.assetURL(h), u2 != url {
                        CrashCatcher.note("视频号", "整段下载失败，改用分片 id=\(item.id)")
                        startPlayer(path: h, url: u2, canFallback: false, viaDownload: false)
                    } else {
                        loadingVideo = false
                    }
                    return
                }
                playURL = local
            }
            let p = viaDownload ? AVPlayer(url: playURL) : (StreamPlay.player(playURL) ?? AVPlayer(url: playURL))
            p.isMuted = false
            p.actionAtItemEnd = .none

            p.automaticallyWaitsToMinimizeStalling = false
            p.currentItem?.preferredForwardBufferDuration = viaDownload ? 2 : 1.2

            if let old = timeObserver, let oldP = player { oldP.removeTimeObserver(old) }
            timeObserver = nil
            installObservers(p)
            if let old = player, old !== p {
                old.pause()
                StreamPlay.cancel(old.currentItem)
            }
            player = p
            if active { p.play() }

            let ticks = canFallback ? 15 : 60
            var moved = false
            for _ in 0..<ticks {
                if let it = p.currentItem {
                    if it.status == .failed { break }
                    if it.status == .readyToPlay, CMTimeGetSeconds(p.currentTime()) > 0.05 {
                        moved = true
                        break
                    }
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
                if player !== p || !active { return }
            }
            if player !== p { return }
            if moved {
                loadingVideo = false
                VideoKernelTelemetry.shared.event("first_frame", itemId: item.id)
                CrashCatcher.note("视频号", "出画面 id=\(item.id) 源=\(path)")
                return
            }
            let why = p.currentItem?.error?.localizedDescription ?? "没等到画面"
            VideoKernelTelemetry.shared.event("playback_error", itemId: item.id)
            CrashCatcher.note("视频号", "加载失败 id=\(item.id) 源=\(path) 原因=\(why)")
            p.pause()
            player = nil
            if canFallback, let fb = item.video, !fb.isEmpty, let u2 = API.shared.assetURL(fb) {
                CrashCatcher.note("视频号", "改用整包 MP4（先下后播）id=\(item.id) 源=\(fb)")
                loadingVideo = true
                startPlayer(path: fb, url: u2, canFallback: false, viaDownload: true)
            } else {
                loadingVideo = false
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

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
