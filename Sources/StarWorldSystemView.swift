import SwiftUI

private enum StarWorldRoute: String, Identifiable, Hashable {
    case moments
    case channels
    case live
    case games
    case music
    case look
    case nearby
    case miniApps
    case search
    case news
    case bottle
    case shop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moments: return Tr("生活圈")
        case .channels: return Tr("视频")
        case .live: return Tr("直播")
        case .games: return Tr("游戏")
        case .music: return Tr("音乐")
        case .look: return Tr("看一看")
        case .nearby: return Tr("附近")
        case .miniApps: return Tr("小程序")
        case .search: return Tr("搜索")
        case .news: return Tr("资讯")
        case .bottle: return Tr("星愿瓶")
        case .shop: return Tr("商城")
        }
    }

    var subtitle: String {
        switch self {
        case .moments: return Tr("朋友与日常")
        case .channels: return Tr("短视频与新内容")
        case .live: return Tr("正在发生")
        case .games: return Tr("轻量游戏")
        case .music: return Tr("继续聆听")
        case .look: return Tr("值得阅读")
        case .nearby: return Tr("同城与周边")
        case .miniApps: return Tr("常用服务")
        case .search: return Tr("查找全部内容")
        case .news: return Tr("今日更新")
        case .bottle: return Tr("随机相遇")
        case .shop: return Tr("商品与服务")
        }
    }

    var symbol: String {
        switch self {
        case .moments: return "photo.stack.fill"
        case .channels: return "play.rectangle.fill"
        case .live: return "dot.radiowaves.left.and.right"
        case .games: return "gamecontroller.fill"
        case .music: return "music.note"
        case .look: return "book.pages.fill"
        case .nearby: return "location.fill"
        case .miniApps: return "square.grid.2x2.fill"
        case .search: return "magnifyingglass"
        case .news: return "newspaper.fill"
        case .bottle: return "waterbottle.fill"
        case .shop: return "bag.fill"
        }
    }

    var tint: Color {
        switch self {
        case .moments: return Color(hex: 0x1677FF)
        case .channels: return Color(hex: 0xF04459)
        case .live: return Color(hex: 0xE83E8C)
        case .games: return Color(hex: 0x7A5AF8)
        case .music: return Color(hex: 0xFA2C56)
        case .look: return Color(hex: 0x0A84FF)
        case .nearby: return Color(hex: 0x2E9E64)
        case .miniApps: return Color(hex: 0x5B6B7A)
        case .search: return Color(hex: 0x6E7882)
        case .news: return Color(hex: 0xD97706)
        case .bottle: return Color(hex: 0x0997A3)
        case .shop: return Color(hex: 0xE26A2C)
        }
    }
}

private struct StarWorldFeature: Identifiable {
    let route: StarWorldRoute
    var id: String { route.id }
}

struct StarWorldSystemView: View {
    var embedded = true

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var route: StarWorldRoute?
    @State private var scanPresented = false

    private let content: [StarWorldFeature] = [
        .init(route: .channels),
        .init(route: .live),
        .init(route: .games),
        .init(route: .music),
        .init(route: .look),
        .init(route: .shop)
    ]

    private let tools: [StarWorldFeature] = [
        .init(route: .nearby),
        .init(route: .miniApps),
        .init(route: .search),
        .init(route: .news),
        .init(route: .bottle)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                C.pageBg.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        momentFeature

                        section(
                            title: Tr("内容"),
                            subtitle: Tr("按兴趣继续探索")
                        ) {
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)
                                ],
                                spacing: 12
                            ) {
                                ForEach(content) { item in
                                    featureTile(item)
                                }
                            }
                        }

                        section(
                            title: Tr("工具"),
                            subtitle: Tr("日常服务集中在这里")
                        ) {
                            VStack(spacing: 0) {
                                ForEach(Array(tools.enumerated()), id: \.element.id) { index, item in
                                    toolRow(item)
                                    if index < tools.count - 1 {
                                        Divider()
                                            .overlay(C.hairline)
                                            .padding(.leading, 54)
                                    }
                                }
                            }
                            .background(C.cardBg)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        Text(Tr("内容与服务会随着使用频率自动排序"))
                            .font(pf(12))
                            .foregroundStyle(C.subLabel)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, max(28, L.safeBottom + 16))
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                header
            }
            .navigationDestination(item: $route) { route in
                destination(route)
                    .environmentObject(app)
            }
            .fullScreenCover(isPresented: $scanPresented) {
                ScannerView { text in handleScanned(text, app: app) }
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(C.pageBg)
        }
        .tint(C.green)
    }

    private var header: some View {
        HStack(spacing: 12) {
            if !embedded {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(Tr("世界"))
                    .font(pf(28, .bold))
                    .foregroundStyle(C.label)
                Text(Tr("内容、工具与服务"))
                    .font(pf(12.5))
                    .foregroundStyle(C.subLabel)
            }

            Spacer(minLength: 8)

            Button {
                scanPresented = true
            } label: {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(C.label)
                    .frame(width: 38, height: 38)
                    .background(C.searchBg, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("扫一扫"))

            Button {
                route = .search
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(C.label)
                    .frame(width: 38, height: 38)
                    .background(C.searchBg, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("搜索"))
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(C.pageBg)
    }

    private var momentFeature: some View {
        Button {
            route = .moments
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Avatar(
                        path: app.me?.avatarPath ?? "",
                        size: 42,
                        radius: 21,
                        circle: true
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(Tr("生活圈"))
                            .font(pf(18, .semibold))
                            .foregroundStyle(C.label)
                        Text(app.moments.isEmpty
                             ? Tr("记录此刻，也看看朋友的日常")
                             : Tr("朋友刚刚更新了动态"))
                            .font(pf(13))
                            .foregroundStyle(C.subLabel)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(C.time)
                        .padding(.top, 4)
                }

                if let moment = app.moments.first {
                    HStack(spacing: 8) {
                        ForEach(Array((moment.images ?? []).prefix(3)), id: \.self) { path in
                            RemoteImage(path: path, mode: .fill, maxSide: 320)
                                .frame(maxWidth: .infinity)
                                .frame(height: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        if moment.images?.isEmpty != false {
                            Text((moment.content ?? "").isEmpty
                                 ? Tr("分享了一段新内容")
                                 : (moment.content ?? ""))
                                .font(pf(15))
                                .foregroundStyle(C.label)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 3)
                        }
                    }
                }
            }
            .padding(16)
            .background(C.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(C.hairline, lineWidth: 0.7)
            }
        }
        .buttonStyle(StarWorldPressStyle())
    }

    private func section<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(pf(18, .semibold))
                    .foregroundStyle(C.label)
                Spacer()
                Text(subtitle)
                    .font(pf(11.5))
                    .foregroundStyle(C.subLabel)
            }
            content()
        }
    }

    private func featureTile(_ item: StarWorldFeature) -> some View {
        Button {
            route = item.route
        } label: {
            HStack(spacing: 11) {
                Image(systemName: item.route.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(item.route.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.route.title)
                        .font(pf(15.5, .semibold))
                        .foregroundStyle(C.label)
                        .lineLimit(1)
                    Text(item.route.subtitle)
                        .font(pf(11.5))
                        .foregroundStyle(C.subLabel)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(C.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(C.hairline, lineWidth: 0.6)
            }
        }
        .buttonStyle(StarWorldPressStyle())
    }

    private func toolRow(_ item: StarWorldFeature) -> some View {
        Button {
            route = item.route
        } label: {
            HStack(spacing: 11) {
                Image(systemName: item.route.symbol)
                    .font(.system(size: 15.5, weight: .medium))
                    .foregroundStyle(item.route.tint)
                    .frame(width: 32, height: 32)
                    .background(item.route.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(item.route.title)
                    .font(pf(16))
                    .foregroundStyle(C.label)

                Spacer(minLength: 8)

                Text(item.route.subtitle)
                    .font(pf(12))
                    .foregroundStyle(C.subLabel)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(C.time)
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(StarWorldRowPressStyle())
    }

    @ViewBuilder
    private func destination(_ route: StarWorldRoute) -> some View {
        switch route {
        case .moments: MomentsView()
        case .channels: ChannelsView()
        case .live: LiveListView()
        case .games: GamesPageView()
        case .music: ListenView(onLeave: { self.route = nil })
        case .look: LookView()
        case .nearby: NearbyPageView()
        case .miniApps: MiniAppsView(modal: false)
        case .search: SearchAllView()
        case .news: NewsView(modal: true)
        case .bottle: BottlePageView()
        case .shop: MallAuthGate { MallNativeView(app: app) }
        }
    }
}

private struct StarWorldPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct StarWorldRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed
                        ? C.label.opacity(0.045)
                        : Color.clear)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
