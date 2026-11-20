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
                onClose: onClose
            )

            readerPanel
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            currentIndex = min(max(0, startIndex), max(0, paths.count - 1))
        }
        .onChange(of: moment.likedByMe) { _ in
            likedOverride = nil
        }
    }

    private var readerPanel: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                    expanded.toggle()
                }
            } label: {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: 38, height: 5)
                    .frame(maxWidth: .infinity)
                    .frame(height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onEnded { value in
                        guard abs(value.translation.height) > 24 else { return }
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                            expanded = value.translation.height < 0
                        }
                    }
            )
            .accessibilityLabel(expanded ? Tr("收起原文") : Tr("展开原文"))

            HStack(alignment: .top, spacing: 10) {
                Avatar(
                    path: moment.author?.avatarPath ?? "",
                    size: 34,
                    radius: 17,
                    circle: true
                )
                .contentShape(Circle())
                .onTapGesture {
                    if let user = moment.author { onOpenAvatar(user) }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(moment.author?.name ?? "")
                        .font(systemTextFont(14.5, .semibold, relativeTo: .subheadline))
                        .foregroundColor(C.link)
                        .lineLimit(1)

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
                    .font(systemTextFont(11.5, .regular, relativeTo: .caption1))
                    .foregroundColor(C.subLabel)
                }

                Spacer(minLength: 8)

                Text("\(min(currentIndex + 1, paths.count)) / \(paths.count)")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundColor(C.subLabel)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            if let text = moment.content?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                Text(RichText.linkified(text))
                    .font(systemTextFont(14.5, .regular, relativeTo: .body))
                    .foregroundColor(C.label)
                    .lineSpacing(4)
                    .lineLimit(expanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }

            if expanded, !comments.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(comments.prefix(4).enumerated()), id: \.offset) { _, comment in
                        let name = comment.nickname ?? ""
                        let text = comment.content ?? ""
                        (Text("\(name)：").foregroundColor(C.link)
                         + Text(text).foregroundColor(C.label))
                            .font(systemTextFont(12.5, .regular, relativeTo: .caption1))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if comments.count > 4 {
                        Button(action: onOpenComments) {
                            Text(Tr("查看全部") + " \(comments.count) " + Tr("条评论"))
                                .font(systemTextFont(12.2, .medium, relativeTo: .caption1))
                                .foregroundColor(C.subLabel)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .transition(.opacity)
            }

            Divider().opacity(0.45)

            HStack(spacing: 18) {
                Button {
                    likedOverride = !showingLiked
                    onLike()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: showingLiked ? "heart.fill" : "heart")
                            .font(.system(size: 18, weight: .regular))
                        if showingLikeCount > 0 {
                            Text("\(showingLikeCount)")
                                .font(systemTextFont(12, .medium, relativeTo: .caption1))
                        }
                    }
                    .foregroundColor(showingLiked
                                     ? Color(hex: 0xFF3B4D)
                                     : C.label)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showingLiked ? Tr("取消赞") : Tr("赞"))

                Button(action: onOpenComments) {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 17, weight: .regular))
                        if !comments.isEmpty {
                            Text("\(comments.count)")
                                .font(systemTextFont(12, .medium, relativeTo: .caption1))
                        }
                    }
                    .foregroundColor(C.label)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Tr("评论"))

                if !likes.isEmpty {
                    Button {
                        onOpenLikes(likes)
                    } label: {
                        HStack(spacing: -6) {
                            ForEach(Array(likes.prefix(4).enumerated()), id: \.offset) { _, like in
                                likeAvatar(like)
                            }
                        }
                        .frame(height: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Tr("查看点赞的人"))
                }

                Spacer(minLength: 0)

                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                        expanded.toggle()
                    }
                } label: {
                    Image(systemName: expanded
                          ? "chevron.down"
                          : "chevron.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(C.subLabel)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
        }
        .padding(.bottom, max(8, L.safeBottom))
        .frame(maxWidth: .infinity)
        .background(C.pageBg)
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 20,
            topTrailingRadius: 20,
            style: .continuous
        ))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: 20,
                topTrailingRadius: 20,
                style: .continuous
            )
            .stroke(Color.primary.opacity(0.07), lineWidth: 0.6)
        }
        .shadow(color: Color.black.opacity(0.24), radius: 18, x: 0, y: -4)
    }

    @ViewBuilder
    private func likeAvatar(_ like: MomentLike) -> some View {
        let name = like.nickname ?? Tr("星友")
        let path = like.userId.map(avatarPathFor) ?? ""

        if path.isEmpty {
            Text(String(name.prefix(1)))
                .font(.system(size: 8.5, weight: .bold))
                .foregroundColor(C.subLabel)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(0.08)))
                .overlay(Circle().stroke(C.pageBg, lineWidth: 2))
        } else {
            Avatar(path: path, size: 22, radius: 11, circle: true)
                .overlay(Circle().stroke(C.pageBg, lineWidth: 2))
        }
    }
}
