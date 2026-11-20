import SwiftUI
import UIKit
import AVFoundation

/// 生活圈主页的单列编辑流。只使用不透明语义底色和细分割线，
/// 不再叠加实时玻璃或阴影，避免长列表滚动时持续触发合成开销。
struct MomentFeedCard: View {
    let moment: Moment
    let dateText: String
    let availableWidth: CGFloat
    let onOpenComments: () -> Void
    let onOpenImage: (Int) -> Void
    let onOpenVideo: (URL) -> Void
    let onOpenAvatar: (User) -> Void
    let onOpenLikes: ([MomentLike]) -> Void
    let avatarPathFor: (String) -> String
    let isFriend: (String) -> Bool
    let onLike: () -> Void
    let onMore: () -> Void

    @State private var likedOverride: Bool?
    @State private var likePulse = false
    @State private var likeBurst = 0

    private var images: [String] { moment.images ?? [] }
    private var isVideo: Bool { !(moment.video ?? "").isEmpty }
    private var likes: [MomentLike] { moment.likes ?? [] }
    private var comments: [MomentComment] { moment.comments ?? [] }
    private var showingLiked: Bool { likedOverride ?? (moment.likedByMe == true) }
    private let cardInset: CGFloat = 9
    private let contentInset: CGFloat = 14
    private var socialSurface: Color {
        Color.dyn(0xF7F7F9, 0x121214)
    }
    private var mediaWidth: CGFloat {
        max(1, availableWidth - (cardInset + contentInset) * 2)
    }

    private var showingLikeCount: Int {
        let base = likes.count
        guard let likedOverride else { return base }
        if likedOverride == (moment.likedByMe == true) { return base }
        return max(0, base + (likedOverride ? 1 : -1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let promotion = moment.promotion {
                promotionBanner(promotion)
                    .padding(.bottom, 9)
            }

            postHeader

            if let text = moment.content?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                Text(MomentTextLayout.attributed(text, size: 15.5))
                    .font(systemTextFont(15.5, .regular, relativeTo: .body))
                    .foregroundColor(C.label)
                    .tracking(0.08)
                    .lineSpacing(5.15)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 11)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpenComments)
                    .onLongPressGesture(minimumDuration: 0.45, maximumDistance: 28) {
                        if moment.mine == true { onMore() }
                    }
            }

            if !images.isEmpty || isVideo {
                media
                    .padding(.top, 12)
            }

            actionRow
                .padding(.top, 10)

            socialContext
                .padding(.top, 9)
        }
        .padding(.horizontal, contentInset)
        .padding(.top, 13)
        .padding(.bottom, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(C.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.065), lineWidth: 0.7)
        }
        .padding(.horizontal, cardInset)
        .padding(.vertical, 5)
        .background(C.pageBg)
        .onChange(of: moment.likedByMe) { _ in
            likedOverride = nil
        }
    }

    private func promotionBanner(_ promotion: MomentPromotion) -> some View {
        HStack(spacing: 7) {
            Text((promotion.label ?? Tr("推广")).uppercased())
                .font(systemTextFont(9.5, .bold, relativeTo: .caption2))
                .tracking(0.8)
                .foregroundColor(Color(hex: 0xA66B28))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color(hex: 0xF4E7D5), in: Capsule())

            Text(promotion.sponsor ?? promotion.disclosure ?? Tr("品牌内容"))
                .font(systemTextFont(11.5, .medium, relativeTo: .caption1))
                .foregroundColor(C.subLabel)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(Tr("广告"))
                .font(systemTextFont(9.5, .medium, relativeTo: .caption2))
                .foregroundColor(C.subLabel.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .frame(height: 31)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.dyn(0xFBF7F1, 0x211C16))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color(hex: 0xA66B28).opacity(0.12), lineWidth: 0.6)
        }
    }

    private var postHeader: some View {
        HStack(alignment: .center, spacing: 9.5) {
            Avatar(path: moment.author?.avatarPath ?? "",
                   size: 43,
                   radius: 21.5,
                   circle: true)
                .contentShape(Circle())
                .onTapGesture {
                    if let user = moment.author { onOpenAvatar(user) }
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(moment.author?.name ?? "")
                        .font(systemTextFont(15.8, .medium, relativeTo: .headline))
                        .foregroundColor(C.link)
                        .lineLimit(1)

                    if moment.pinned == true {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(C.subLabel)
                    }
                }

                HStack(spacing: 5) {
                    Text(dateText)
                    if let location = moment.location?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !location.isEmpty {
                        Text("·")
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 10.5, weight: .medium))
                        Text(location).lineLimit(1)
                    }
                }
                .font(systemTextFont(11.6, .regular, relativeTo: .caption1))
                .foregroundColor(C.subLabel)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if let user = moment.author { onOpenAvatar(user) }
            }

            Spacer(minLength: 8)

            Button(action: onMore) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(C.subLabel)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("更多"))
        }
    }

    @ViewBuilder
    private var media: some View {
        if isVideo {
            videoTile
        } else {
            MomentFeedImageGrid(images: images,
                                sizes: moment.imageSizes ?? [:],
                                width: mediaWidth,
                                onTap: onOpenImage)
        }
    }

    private var videoTile: some View {
        let knownRatio: CGFloat = (moment.videoW ?? 0) > 0 && (moment.videoH ?? 0) > 0
            ? CGFloat(moment.videoW!) / CGFloat(moment.videoH!)
            : 1.25
        let size = MomentMediaLayout.singleVideoSize(
            knownRatio: knownRatio,
            width: mediaWidth
        )
        let raw = moment.video ?? ""
        let full = raw.hasPrefix("http") ? raw : API.shared.base + raw
        let videoURL = URL(string: full)

        return Button {
            if let videoURL { onOpenVideo(videoURL) }
        } label: {
            ZStack {
                if let videoURL {
                    MomentAutoplayVideo(
                        url: videoURL,
                        cover: moment.videoCover ?? ""
                    )
                } else {
                    C.searchBg
                }

                if (moment.videoSeconds ?? 0) > 0 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(Self.timeText(moment.videoSeconds ?? 0))
                                .font(systemTextFont(11.5, .medium, relativeTo: .caption2))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.black.opacity(0.62)))
                        }
                    }
                    .padding(8)
                }

                if moment.pinned == true {
                    VStack {
                        HStack {
                            Label(Tr("置顶"), systemImage: "pin.fill")
                                .font(systemTextFont(10.5, .semibold, relativeTo: .caption2))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.black.opacity(0.62)))
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(8)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.075), lineWidth: 0.6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var actionRow: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                Button {
                    if !showingLiked {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        likeBurst += 1
                    }
                    likedOverride = !showingLiked
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        likePulse = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        likePulse = false
                    }
                    onLike()
                } label: {
                    HStack(spacing: 5) {
                        ZStack {
                            if likeBurst > 0 {
                                MomentLikeParticleBurst(seed: likeBurst)
                                    .id(likeBurst)
                            }
                            Image(systemName: showingLiked ? "heart.fill" : "heart")
                                .font(.system(size: 17, weight: .regular))
                                .scaleEffect(likePulse ? 1.16 : 1)
                        }
                        .frame(width: 20, height: 22)
                        if showingLikeCount > 0 {
                            Text("\(showingLikeCount)")
                                .font(systemTextFont(11.8, .medium, relativeTo: .caption1))
                        }
                    }
                    .foregroundColor(showingLiked ? Color(hex: 0xFF3B4D) : C.subLabel)
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showingLiked ? Tr("取消赞") : Tr("赞"))

                Button(action: onOpenComments) {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 16.5, weight: .regular))
                        if !comments.isEmpty {
                            Text("\(comments.count)")
                                .font(systemTextFont(11.8, .medium, relativeTo: .caption1))
                        }
                    }
                    .foregroundColor(C.subLabel)
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Tr("评论"))

                Button(action: onMore) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundColor(C.subLabel)
                        .frame(width: 31, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Tr("更多"))
            }
            .padding(.horizontal, 3)
            .background(Capsule().fill(Color.primary.opacity(0.045)))
            .overlay(Capsule().stroke(Color.primary.opacity(0.055), lineWidth: 0.6))
        }
    }

    @ViewBuilder
    private var socialContext: some View {
        if !likes.isEmpty || !comments.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if !likes.isEmpty {
                    likesSummaryButton
                }

                ForEach(Array(comments.prefix(2).enumerated()), id: \.offset) { _, comment in
                    commentLine(comment)
                }

                if comments.count > 2 {
                    Button(action: onOpenComments) {
                        Text(Lang.isEnglish
                             ? "View all \(comments.count) comments"
                             : "查看全部 \(comments.count) 条评论")
                            .font(systemTextFont(12.2, .medium, relativeTo: .caption1))
                            .foregroundColor(C.label.opacity(0.72))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(socialSurface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.primary.opacity(0.055), lineWidth: 0.6)
            }
        }
    }

    private var likesSummaryButton: some View {
        Button {
            onOpenLikes(stableOrderedLikes)
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: -7) {
                    ForEach(Array(stableOrderedLikes.prefix(6).enumerated()), id: \.offset) { _, like in
                        likeAvatar(like, size: 22)
                            .overlay(Circle().stroke(socialSurface, lineWidth: 2))
                    }
                    if stableOrderedLikes.count > 6 {
                        Text("+\(stableOrderedLikes.count - 6)")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(C.subLabel)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.primary.opacity(0.07)))
                            .overlay(Circle().stroke(socialSurface, lineWidth: 2))
                    }
                }
                .frame(height: 22)

                Text(localizedLikeSummary)
                    .font(systemTextFont(12.3, .medium, relativeTo: .caption1))
                    .foregroundColor(C.label)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(C.subLabel)
            }
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Lang.isEnglish
                            ? "\(showingLikeCount) people like this. View all."
                            : "\(showingLikeCount) 人觉得不错，查看全部")
    }

    @ViewBuilder
    private func likeAvatar(_ like: MomentLike, size: CGFloat) -> some View {
        let path = like.userId.map(avatarPathFor) ?? ""
        if !path.isEmpty {
            Avatar(path: path, size: size, radius: size / 2, circle: true)
        } else {
            Text(String((like.nickname ?? Tr("星")).prefix(1)))
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundColor(C.subLabel)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.dyn(0xECECF0, 0x242426)))
        }
    }

    private var stableOrderedLikes: [MomentLike] {
        var seen = Set<String>()
        let unique = likes.filter { like in
            let key = like.userId?.isEmpty == false ? like.userId! : (like.nickname ?? UUID().uuidString)
            return seen.insert(key).inserted
        }
        let friends = unique.filter { isFriend($0.userId ?? "") }
        let others = unique.filter { !isFriend($0.userId ?? "") }
        return friends + others
    }

    private var localizedLikeSummary: String {
        let names = likes.compactMap(\.nickname).filter { !$0.isEmpty }
        let count = showingLikeCount

        if Lang.isEnglish {
            switch names.count {
            case 0: return count == 1 ? "1 person likes this" : "\(count) people like this"
            case 1: return count > 1 ? "\(names[0]) and \(count - 1) others" : names[0]
            case 2: return count > 2 ? "\(names[0]), \(names[1]) and \(count - 2) others"
                : "\(names[0]) and \(names[1])"
            default: return "\(names[0]), \(names[1]) and \(count - 2) others"
            }
        }

        switch names.count {
        case 0: return "\(count) 人觉得不错"
        case 1: return count > 1 ? "\(names[0])等 \(count) 人" : names[0]
        case 2: return count > 2 ? "\(names[0])、\(names[1])等 \(count) 人"
            : "\(names[0])、\(names[1])"
        default: return "\(names[0])、\(names[1])等 \(count) 人"
        }
    }

    private func commentLine(_ comment: MomentComment) -> some View {
        let name = comment.nickname ?? ""
        let text = comment.content ?? ""
        let replyName = (comment.replyToName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let attribution = replyName.isEmpty
            ? "\(name)："
            : "\(name) 回复 \(replyName)："

        return (Text(attribution).foregroundColor(C.link)
                + Text(text).foregroundColor(C.label))
            .font(systemTextFont(12.5, .regular, relativeTo: .caption1))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpenComments)
    }

    private static func timeText(_ seconds: Int) -> String {
        String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }
}

struct MomentLikesSheet: View {
    let likes: [MomentLike]

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var uniqueLikes: [MomentLike] {
        var seen = Set<String>()
        return likes.filter { like in
            let key = like.userId?.isEmpty == false ? like.userId! : (like.nickname ?? UUID().uuidString)
            return seen.insert(key).inserted
        }
    }

    private var filteredLikes: [MomentLike] {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return uniqueLikes }
        return uniqueLikes.filter { ($0.nickname ?? "").localizedCaseInsensitiveContains(key) }
    }

    private var friends: [MomentLike] {
        filteredLikes.filter { app.contact(for: $0.userId ?? "") != nil }
    }

    private var others: [MomentLike] {
        filteredLikes.filter { app.contact(for: $0.userId ?? "") == nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.dyn(0xC9C9CE, 0x48484D))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            HStack(spacing: 10) {
                Text(Lang.isEnglish
                     ? "\(uniqueLikes.count) likes"
                     : "\(uniqueLikes.count) 人觉得不错")
                    .font(systemTextFont(18, .semibold, relativeTo: .headline))
                    .foregroundColor(C.label)
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(C.subLabel)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.dyn(0xF0F0F3, 0x1C1C1E)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Tr("关闭"))
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 10)

            if uniqueLikes.count > 24 {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(C.subLabel)
                    TextField(Lang.isEnglish ? "Search people" : "搜索点赞的人", text: $query)
                        .font(systemTextFont(14.5, .regular, relativeTo: .body))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(C.subLabel)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 11)
                .frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.dyn(0xF1F1F4, 0x1C1C1E)))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !friends.isEmpty {
                        sectionHeader(Lang.isEnglish ? "Friends" : "好友", count: friends.count)
                        ForEach(Array(friends.enumerated()), id: \.offset) { index, like in
                            likeRow(like, relationship: Lang.isEnglish ? "Friend" : "好友")
                            if index < friends.count - 1 {
                                HairLine(inset: 67)
                            }
                        }
                    }

                    if !others.isEmpty {
                        sectionHeader(Lang.isEnglish ? "Star friends" : "星友", count: others.count)
                        ForEach(Array(others.enumerated()), id: \.offset) { index, like in
                            likeRow(like, relationship: Lang.isEnglish ? "Star friend" : "星友")
                            if index < others.count - 1 {
                                HairLine(inset: 67)
                            }
                        }
                    }

                    if filteredLikes.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .font(.system(size: 28, weight: .light))
                                .foregroundColor(C.subLabel)
                            Text(Lang.isEnglish ? "No matching people" : "没有找到这个人")
                                .font(systemTextFont(14, .regular, relativeTo: .body))
                                .foregroundColor(C.subLabel)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 54)
                    }

                    Color.clear.frame(height: max(24, L.safeBottom + 12))
                }
            }
        }
        .background(C.pageBg.ignoresSafeArea())
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Text("\(count)")
                .foregroundColor(C.subLabel)
            Spacer(minLength: 0)
        }
        .font(systemTextFont(13, .semibold, relativeTo: .caption1))
        .foregroundColor(C.label)
        .padding(.horizontal, 18)
        .padding(.top, 15)
        .padding(.bottom, 6)
    }

    private func likeRow(_ like: MomentLike, relationship: String) -> some View {
        let contact = like.userId.flatMap { app.contact(for: $0) }
        let name = contact?.name ?? like.nickname ?? Tr("星友")
        let avatar = contact?.avatarPath ?? ""

        return HStack(spacing: 12) {
            if avatar.isEmpty {
                Text(String(name.prefix(1)))
                    .font(systemTextFont(16, .semibold, relativeTo: .body))
                    .foregroundColor(C.subLabel)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.dyn(0xECECF0, 0x242426)))
            } else {
                Avatar(path: avatar, size: 44, radius: 22, circle: true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(systemTextFont(15.5, .medium, relativeTo: .body))
                    .foregroundColor(C.label)
                    .lineLimit(1)
                Text(relationship)
                    .font(systemTextFont(12, .regular, relativeTo: .caption1))
                    .foregroundColor(C.subLabel)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 18)
        .frame(height: 60)
    }
}

struct MomentLikesPresenter: ViewModifier {
    let likes: [MomentLike]
    @Binding var isPresented: Bool
    @EnvironmentObject private var app: AppState

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            MomentLikesSheet(likes: likes)
                .environmentObject(app)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
        }
    }
}

private enum MomentTextLayout {
    static func normalized(_ raw: String) -> String {
        let unified = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var output: [String] = []
        var blankRun = 0
        for original in unified.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ) {
            let line = String(original)
                .replacingOccurrences(
                    of: #"[ \t]+$"#,
                    with: "",
                    options: .regularExpression
                )
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blankRun += 1
                if blankRun <= 1 { output.append("") }
            } else {
                blankRun = 0
                output.append(line)
            }
        }
        while output.first == "" { output.removeFirst() }
        while output.last == "" { output.removeLast() }
        return output.joined(separator: "\n")
    }

    static func attributed(_ raw: String, size: CGFloat) -> AttributedString {
        RichText.lines(normalized(raw), size: size)
    }
}

struct MomentAutoplayVideo: View {
    let url: URL
    let cover: String

    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVPlayer?
    @State private var playing = false
    @State private var lastFrame = CGRect.zero

    var body: some View {
        ZStack {
            if cover.isEmpty {
                Color.black
            } else {
                RemoteImage(path: cover, mode: .fill, maxSide: 1440)
            }

            if let player {
                PlayerLayerView(player: player)
                    .opacity(playing ? 1 : 0)
            }

            if !playing {
                Circle()
                    .fill(Color.black.opacity(0.46))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(.white)
                            .offset(x: 1.2)
                    }
                    .allowsHitTesting(false)
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        evaluate(proxy.frame(in: .global))
                    }
                    .onChange(of: proxy.frame(in: .global)) { frame in
                        evaluate(frame)
                    }
            }
        }
        .onAppear {
            preparePlayer()
            evaluate(lastFrame)
        }
        .onDisappear {
            player?.pause()
            playing = false
        }
        .onChange(of: scenePhase) { _ in
            evaluate(lastFrame)
        }
    }

    private func preparePlayer() {
        guard player == nil else { return }
        let next = AVPlayer(url: url)
        next.isMuted = true
        next.volume = 0
        next.actionAtItemEnd = .pause
        next.automaticallyWaitsToMinimizeStalling = false
        next.currentItem?.preferredForwardBufferDuration = 1.0
        player = next
    }

    private func evaluate(_ frame: CGRect) {
        guard !frame.isEmpty else { return }
        lastFrame = frame

        let screen = UIScreen.main.bounds
        let clipped = frame.intersection(screen)
        let visible = clipped.isNull || frame.height <= 0
            ? 0
            : max(0, min(1, clipped.height / frame.height))
        let safeCenter = frame.midY > L.safeTop + L.navH + 18
            && frame.midY < screen.height - max(20, L.safeBottom)
        let shouldPlay = scenePhase == .active
            && visible >= 0.60
            && (safeCenter || visible >= 0.86)

        guard shouldPlay else {
            player?.pause()
            playing = false
            return
        }

        preparePlayer()
        if let item = player?.currentItem,
           item.duration.isValid,
           !item.duration.isIndefinite,
           item.currentTime() >= item.duration {
            player?.seek(to: .zero)
        }
        player?.playImmediately(atRate: 1)
        playing = true
    }
}

private struct MomentLikeParticleBurst: View {
    private struct Particle: Identifiable {
        let id: Int
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let color: Color
    }

    let seed: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    private let colors: [Color] = [
        Color(hex: 0xFF3B4D),
        Color(hex: 0xFF7A59),
        Color(hex: 0xFFC857),
        Color.white
    ]

    private var particles: [Particle] {
        let count = reduceMotion ? 6 : 14
        return (0..<count).map { index in
            let angle = Double(index) / Double(count) * .pi * 2
            let distance = CGFloat(12 + ((index * 7 + seed * 11) % 13))
            let lift = CGFloat(((index * 5 + seed) % 9) - 4)
            return Particle(
                id: index,
                x: CGFloat(cos(angle)) * distance,
                y: CGFloat(sin(angle)) * distance + lift,
                size: CGFloat(2 + (index % 3)),
                color: colors[index % colors.count]
            )
        }
    }

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .offset(
                        x: expanded ? particle.x : 0,
                        y: expanded ? particle.y : 0
                    )
                    .scaleEffect(expanded ? 0.25 : 1.15)
                    .opacity(expanded ? 0 : 1)
            }
        }
        .frame(width: 30, height: 30)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.52)) {
                expanded = true
            }
        }
        .accessibilityHidden(true)
    }
}

private struct MomentFeedImageGrid: View {
    let images: [String]
    let sizes: [String: [Int]]
    let width: CGFloat
    let onTap: (Int) -> Void

    var body: some View {
        if images.count == 1 {
            singleImage
        } else {
            grid
        }
    }

    private var singleImage: some View {
        let path = images[0]
        let size = sizes[path]
        let ratio = (size?.count ?? 0) >= 2 && (size?[1] ?? 0) > 0
            ? CGFloat(size![0]) / CGFloat(size![1])
            : 4.0 / 3.0
        let fitted = MomentMediaLayout.singleImageSize(knownRatio: ratio, width: width)

        return Button {
            onTap(0)
        } label: {
            RemoteImage(path: path, icon: "photo", maxSide: 1440)
                .frame(width: fitted.width, height: fitted.height)
                .clipShape(RoundedRectangle(
                    cornerRadius: MomentMediaLayout.singleRadius,
                    style: .continuous
                ))
                .overlay {
                    RoundedRectangle(
                        cornerRadius: MomentMediaLayout.singleRadius,
                        style: .continuous
                    )
                        .stroke(Color.primary.opacity(0.075), lineWidth: 0.6)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var grid: some View {
        let columns = MomentMediaLayout.columns(for: images.count)
        let cellSize = MomentMediaLayout.gridCellSize(count: images.count, width: width)
        let gap = MomentMediaLayout.gap
        let gridWidth = cellSize.width * CGFloat(columns)
            + gap * CGFloat(max(0, columns - 1))
        let layout = Array(
            repeating: GridItem(.fixed(cellSize.width), spacing: gap),
            count: columns
        )

        return LazyVGrid(columns: layout, alignment: .leading, spacing: gap) {
            ForEach(Array(images.enumerated()), id: \.offset) { index, path in
                Button {
                    onTap(index)
                } label: {
                    RemoteImage(path: path, icon: "photo", maxSide: 960)
                        .frame(width: cellSize.width, height: cellSize.height)
                        .clipShape(RoundedRectangle(
                            cornerRadius: MomentMediaLayout.gridRadius,
                            style: .continuous
                        ))
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: MomentMediaLayout.gridRadius,
                                style: .continuous
                            )
                                .stroke(Color.primary.opacity(0.07), lineWidth: 0.6)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: gridWidth, alignment: .leading)
    }
}
