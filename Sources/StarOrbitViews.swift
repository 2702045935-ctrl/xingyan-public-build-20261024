import SwiftUI

struct StarOrbitMetric: Identifiable {
    let id = UUID()
    let value: String
    let label: String
}

struct StarOrbitHero: View {
    let kicker: String
    let title: String
    let subtitle: String
    let symbol: String
    var accent: Color = OrbitTheme.jade
    var metrics: [StarOrbitMetric] = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        accent.opacity(0.86),
                        Color.dyn(0x18312A, 0x07100D)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            orbitDecoration

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 7) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 11, weight: .semibold))
                        Text(kicker)
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.25)
                    }
                    .foregroundStyle(Color.white.opacity(0.76))

                    Spacer(minLength: 10)

                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.13)))
                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.7))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.74))
                        .lineLimit(2)
                }

                if !metrics.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(metrics) { metric in
                            HStack(spacing: 5) {
                                Text(metric.value)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Text(metric.label)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.64))
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 25)
                            .background(Capsule().fill(Color.white.opacity(0.11)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.6))
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
        }
    }

    private var orbitDecoration: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.11), lineWidth: 1)
                    .frame(width: 174, height: 174)
                    .position(x: geo.size.width - 12, y: 8)
                Circle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 4, height: 4)
                    .position(x: geo.size.width - 86, y: 26)
            }
        }
        .allowsHitTesting(false)
    }
}

struct StarOrbitIconBadge: View {
    let symbol: String
    var accent: Color = OrbitTheme.jade
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(accent.opacity(0.14))
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .stroke(accent.opacity(0.28), lineWidth: 0.8)
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(accent)
        }
        .frame(width: size, height: size)
    }
}

struct StarOrbitTrailingPill: View {
    let text: String
    var accent: Color = OrbitTheme.jade

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(accent)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(accent.opacity(0.12)))
            .overlay(Capsule().stroke(accent.opacity(0.20), lineWidth: 0.6))
    }
}

struct StarOrbitCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(OrbitTheme.cardBackground())
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct StarOrbitSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(OrbitTheme.tertiary)
            TextField(placeholder, text: $text)
                .font(.system(size: 14.5))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(OrbitTheme.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 42)
        .background(OrbitTheme.field)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(OrbitTheme.divider, lineWidth: 0.7)
        }
    }
}

private struct StarTagGroup: Identifiable {
    let name: String
    let users: [User]
    var id: String { name }
}

struct StarOrbitTagsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""

    private var groups: [StarTagGroup] {
        var grouped: [String: [User]] = [:]
        for user in app.contacts {
            for raw in user.tags ?? [] {
                let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if tag.isEmpty { continue }
                grouped[tag, default: []].append(user)
            }
        }
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        return grouped.map { StarTagGroup(name: $0.key, users: $0.value) }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("标签"), back: { dismiss() })
            ScrollView {
                LazyVStack(spacing: 12) {
                    StarOrbitHero(
                        kicker: "联系人星图",
                        title: Tr("标签"),
                        subtitle: Tr("把重要的人放进你的星轨，关系会更清晰"),
                        symbol: "tag.fill",
                        accent: OrbitTheme.gold,
                        metrics: [
                            StarOrbitMetric(value: "\(groups.count)", label: Tr("个标签")),
                            StarOrbitMetric(value: "\(groups.reduce(0) { $0 + $1.users.count })", label: Tr("次标注"))
                        ]
                    )
                    .padding(.horizontal, 12)

                    StarOrbitSearchField(placeholder: Tr("搜索标签"), text: $keyword)
                        .padding(.horizontal, 12)

                    if groups.isEmpty {
                        emptyState
                    } else {
                        OrbitSectionLabel(text: Tr("我的标签"), count: groups.count)
                            .padding(.horizontal, 17)
                            .padding(.top, 2)

                        ForEach(groups) { group in
                            NavigationLink {
                                StarOrbitTagDetailView(tag: group.name, users: group.users)
                                    .environmentObject(app)
                            } label: {
                                tagCard(group)
                            }
                            .buttonStyle(MenuPressStyle())
                            .padding(.horizontal, 12)
                        }
                    }
                    Spacer().frame(height: 30)
                }
                .padding(.top, 10)
            }
            .refreshable { await app.loadContacts() }
        }
        .background(OrbitTheme.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task { await app.loadContacts() }
    }

    private func tagCard(_ group: StarTagGroup) -> some View {
        StarOrbitCard {
            HStack(spacing: 13) {
                StarOrbitIconBadge(symbol: "tag.fill", accent: OrbitTheme.gold)
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.system(size: 16.5, weight: .semibold))
                        .foregroundStyle(OrbitTheme.ink)
                        .lineLimit(1)
                    Text(group.users.prefix(3).map(\.name).joined(separator: " · "))
                        .font(.system(size: 12.5))
                        .foregroundStyle(OrbitTheme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                StarOrbitTrailingPill(text: "\(group.users.count)", accent: OrbitTheme.gold)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(OrbitTheme.tertiary)
            }
            .padding(.horizontal, 15)
            .frame(height: 72)
            .contentShape(Rectangle())
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            StarOrbitIconBadge(symbol: "sparkles", accent: OrbitTheme.gold, size: 54)
            Text(Tr("还没有标签"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(OrbitTheme.ink)
            Text(Tr("在联系人资料里设置标签，这里会自动形成你的关系星图"))
                .font(.system(size: 13))
                .foregroundStyle(OrbitTheme.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .padding(.horizontal, 26)
        .background(OrbitTheme.cardBackground())
        .clipShape(OrbitTheme.card)
        .padding(.horizontal, 12)
    }
}

struct StarOrbitTagDetailView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    let tag: String
    let users: [User]

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: tag, back: { dismiss() })
            ScrollView {
                LazyVStack(spacing: 10) {
                    StarOrbitHero(
                        kicker: "星轨成员",
                        title: tag,
                        subtitle: Tr("同一星轨上的联系人"),
                        symbol: "point.3.connected.trianglepath.dotted",
                        accent: OrbitTheme.gold,
                        metrics: [StarOrbitMetric(value: "\(users.count)", label: Tr("位联系人"))]
                    )
                    .padding(.horizontal, 12)

                    ForEach(users) { user in
                        NavigationLink {
                            ContactCardView(
                                user: user,
                                onOpenChat: { chat in app.openChat = chat },
                                onOpenMoments: { _ in }
                            )
                            .environmentObject(app)
                        } label: {
                            StarOrbitCard {
                                HStack(spacing: 13) {
                                    Avatar(path: user.avatarPath, size: 44, radius: 12)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(user.name)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundStyle(OrbitTheme.ink)
                                        Text("@" + (user.username ?? ""))
                                            .font(.system(size: 12))
                                            .foregroundStyle(OrbitTheme.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(OrbitTheme.tertiary)
                                }
                                .padding(.horizontal, 15)
                                .frame(height: 68)
                                .contentShape(Rectangle())
                            }
                        }
                        .buttonStyle(MenuPressStyle())
                        .padding(.horizontal, 12)
                    }
                    Spacer().frame(height: 30)
                }
                .padding(.top, 10)
            }
        }
        .background(OrbitTheme.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
    }
}
