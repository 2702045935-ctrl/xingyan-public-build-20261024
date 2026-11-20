import SwiftUI
import UIKit

struct MomentPhotoReader: View {
    let moment: Moment
    let paths: [String]
    let startIndex: Int
    let onClose: () -> Void
    let onLike: () -> Void
    let onOpenComments: () -> Void
    let onOpenAvatar: (User) -> Void
    let onOpenLikes: ([MomentLike]) -> Void
    let avatarPathFor: (String) -> String

    @State private var expanded = false
    @State private var likedOverride: Bool?
    @State private var currentIndex = 0
    @State private var chromeVisible = true

    private var likes: [MomentLike] {
        var seen = Set<String>()
        return (moment.likes ?? []).filter { like in
            let key = like.userId?.isEmpty == false
                ? like.userId!
                : (like.nickname ?? UUID().uuidString)
            return seen.insert(key).inserted
        }
    }

    private var comments: [MomentComment] { moment.comments ?? [] }
    private var bodyText: String {
        moment.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    private var readerLink: Color { Color(hex: 0x8DA9D8) }
    private var readerText: Color { Color.white.opacity(0.92) }
    private var readerSecondary: Color { Color.white.opacity(0.56) }
    private var readerSurface: Color { Color(hex: 0x0C0C0E) }
    private var showingLiked: Bool {
        likedOverride ?? (moment.likedByMe == true)
    }
    private var showingLikeCount: Int {
        let base = likes.count
        guard let likedOverride else { return base }
        if likedOverride == (moment.likedByMe == true) { return base }
        return max(0, base + (likedOverride ? 1 : -1))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            PhotoPager(
                paths: paths,
                startIndex: startIndex,
                showActions: true,
                onIndexChange: { currentIndex = $0 },
                onChromeVisibilityChange: { chromeVisible = $0 },
                onClose: onClose
            )

            readerPanel
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .opacity(chromeVisible || expanded ? 1 : 0)
                .allowsHitTesting(chromeVisible || expanded)
                .animation(.easeInOut(duration: 0.2), value: chromeVisible)
                .zIndex(2)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            currentIndex = min(max(0, startIndex), max(0, paths.count - 1))
            chromeVisible = true
        }
        .onChange(of: moment.likedByMe) { _ in
            likedOverride = nil
        }
    }

    private var readerPanel: some View {
        VStack(spacing: 0) {
            readerHandle

            HStack(alignment: .center, spacing: 10) {
                Avatar(
                    path: moment.author?.avatarPath ?? "",
                    size: 32,
                    radius: 16,
                    circle: true
                )
                .contentShape(Circle())
                .onTapGesture {
                    if let user = moment.author { onOpenAvatar(user) }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(moment.author?.name ?? "")
                            .font(systemTextFont(14.2, .semibold, relativeTo: .subheadline))
                            .foregroundColor(readerLink)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        Text("\(min(currentIndex + 1, paths.count)) / \(paths.count)")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundColor(readerSecondary)
                    }

                    HStack(spacing: 5) {
                        Text(TimeFmt.ago(moment.createdAt))
                        if let location = moment.location?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                           !location.isEmpty {
                            Text("·")
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 9.5, weight: .medium))
                            Text(location).lineLimit(1)
                        }
                    }
                    .font(systemTextFont(11.2, .regular, relativeTo: .caption1))
                    .foregroundColor(readerSecondary)

                    if !expanded, !bodyText.isEmpty {
                        Text(RichText.linkified(bodyText))
                            .font(systemTextFont(13.2, .regular, relativeTo: .subheadline))
                            .foregroundColor(readerText)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Button {
                    likedOverride = !showingLiked
                    onLike()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: showingLiked ? "heart.fill" : "heart")
                            .font(.system(size: 17, weight: .regular))
                        if showingLikeCount > 0 {
                            Text("\(showingLikeCount)")
                                .font(systemTextFont(11.2, .medium, relativeTo: .caption1))
                        }
                    }
                    .foregroundColor(showingLiked
                                     ? Color(hex: 0xFF3B4D)
                                     : readerText)
                    .frame(minWidth: 30, minHeight: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showingLiked ? Tr("取消赞") : Tr("赞"))

                Button(action: onOpenComments) {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 17, weight: .regular))
                        if !comments.isEmpty {
                            Text("\(comments.count)")
                                .font(systemTextFont(11.2, .medium, relativeTo: .caption1))
                        }
                    }
                    .foregroundColor(readerText)
                    .frame(minWidth: 30, minHeight: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Tr("评论"))

                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                        expanded.toggle()
                    }
                } label: {
                    Image(systemName: expanded
                          ? "chevron.down"
                          : "chevron.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(readerSecondary)
                        .frame(width: 30, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 15)
            .padding(.top, 7)
            .padding(.bottom, 10)

            if expanded {
                Divider()
                    .overlay(Color.white.opacity(0.12))
                    .padding(.horizontal, 15)
                    .transition(.opacity)

                expandedReader
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.bottom, max(6, L.safeBottom))
        .frame(maxWidth: .infinity)
        .background {
            Color(hex: 0x0C0C0E)
                .opacity(0.94)
                .background(.ultraThinMaterial)
        }
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 18,
            topTrailingRadius: 18,
            style: .continuous
        ))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: 18,
                topTrailingRadius: 18,
                style: .continuous
            )
            .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
        }
        .shadow(color: Color.black.opacity(0.32), radius: 14, x: 0, y: -3)
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    guard abs(value.translation.height) > 28 else { return }
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                        expanded = value.translation.height < 0
                    }
                }
        )
    }

    private var readerHandle: some View {
        Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                expanded.toggle()
            }
        } label: {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.24))
                .frame(width: 34, height: 4)
                .frame(maxWidth: .infinity)
                .frame(height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expanded ? Tr("收起原文") : Tr("展开原文"))
    }

    private var expandedReader: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !bodyText.isEmpty {
                    Text(RichText.linkified(bodyText))
                        .font(systemTextFont(14.2, .regular, relativeTo: .body))
                        .foregroundColor(readerText)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !likes.isEmpty {
                    Button {
                        onOpenLikes(likes)
                    } label: {
                        HStack(spacing: 8) {
                            HStack(spacing: -6) {
                                ForEach(Array(likes.prefix(5).enumerated()), id: \.offset) { _, like in
                                    likeAvatar(like)
                                }
                            }
                            .frame(height: 22)

                            Text(likes.compactMap(\.nickname)
                                .filter { !$0.isEmpty }
                                .prefix(2)
                                .joined(separator: "、"))
                                .font(systemTextFont(12.2, .medium, relativeTo: .caption1))
                                .foregroundColor(readerText)
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if !comments.isEmpty {
                    Divider()
                        .overlay(Color.white.opacity(0.11))

                    ForEach(Array(comments.prefix(4).enumerated()), id: \.offset) { _, comment in
                        let name = comment.nickname ?? ""
                        let text = comment.content ?? ""
                        (Text("\(name)：").foregroundColor(readerLink)
                         + Text(text).foregroundColor(readerText))
                            .font(systemTextFont(12.5, .regular, relativeTo: .caption1))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if comments.count > 4 {
                        Button(action: onOpenComments) {
                            Text(Tr("查看全部") + " \(comments.count) " + Tr("条评论"))
                                .font(systemTextFont(12.2, .medium, relativeTo: .caption1))
                                .foregroundColor(readerSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .frame(maxHeight: 300)
    }

    @ViewBuilder
    private func likeAvatar(_ like: MomentLike) -> some View {
        let name = like.nickname ?? Tr("星友")
        let path = like.userId.map(avatarPathFor) ?? ""

        if path.isEmpty {
            Text(String(name.prefix(1)))
                .font(.system(size: 8.5, weight: .bold))
                .foregroundColor(readerSecondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(0.10)))
                .overlay(Circle().stroke(readerSurface, lineWidth: 2))
        } else {
            Avatar(path: path, size: 22, radius: 11, circle: true)
                .overlay(Circle().stroke(readerSurface, lineWidth: 2))
        }
    }
}
