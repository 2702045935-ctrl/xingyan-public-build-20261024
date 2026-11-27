import SwiftUI

struct MomentLikesSheet: View {
    let likes: [MomentLike]

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var uniqueLikes: [MomentLike] {
        var seen = Set<String>()
        return likes.filter { like in
            let key = like.userId?.isEmpty == false
                ? like.userId! : (like.nickname ?? UUID().uuidString)
            return seen.insert(key).inserted
        }
    }

    private var filteredLikes: [MomentLike] {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return uniqueLikes }
        return uniqueLikes.filter {
            ($0.nickname ?? "").localizedCaseInsensitiveContains(key)
        }
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
                    TextField(Lang.isEnglish ? "Search people" : "搜索点赞的人",
                              text: $query)
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
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.dyn(0xF1F1F4, 0x1C1C1E))
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !friends.isEmpty {
                        sectionHeader(Lang.isEnglish ? "Friends" : "好友",
                                      count: friends.count)
                        ForEach(Array(friends.enumerated()), id: \.offset) { index, like in
                            likeRow(like, relationship: Lang.isEnglish ? "Friend" : "好友")
                            if index < friends.count - 1 {
                                HairLine(inset: 67)
                            }
                        }
                    }

                    if !others.isEmpty {
                        sectionHeader(Lang.isEnglish ? "Star friends" : "星友",
                                      count: others.count)
                        ForEach(Array(others.enumerated()), id: \.offset) { index, like in
                            likeRow(like,
                                    relationship: Lang.isEnglish ? "Star friend" : "星友")
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
