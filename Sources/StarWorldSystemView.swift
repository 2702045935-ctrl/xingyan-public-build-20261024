import SwiftUI

private enum StarWorldRoute: String, Identifiable, Hashable {
    case moments
    case channels
    case live
    case games
    case music
    case look
    case shop
    case nearby
    case miniApps
    case search
    case news
    case bottle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moments: return Tr("生活圈")
        case .channels: return Tr("视频")
        case .live: return Tr("直播")
        case .games: return Tr("游戏")
        case .music: return Tr("音乐")
        case .look: return Tr("看一看")
        case .shop: return Tr("商城")
        case .nearby: return Tr("附近")
        case .miniApps: return Tr("小程序")
        case .search: return Tr("搜索")
        case .news: return Tr("资讯")
        case .bottle: return Tr("星愿瓶")
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
        case .shop: return Tr("商品与服务")
        case .nearby: return Tr("同城与周边")
        case .miniApps: return Tr("常用服务")
        case .search: return Tr("查找全部内容")
        case .news: return Tr("今日更新")
        case .bottle: return Tr("随机相遇")
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
        case .shop: return "bag.fill"
        case .nearby: return "location.fill"
        case .miniApps: return "square.grid.2x2.fill"
        case .search: return "magnifyingglass"
        case .news: return "newspaper.fill"
        case .bottle: return "waterbottle.fill"
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
        case .shop: return Color(hex: 0xE26A2C)
        case .nearby: return Color(hex: 0x2E9E64)
        case .miniApps: return Color(hex: 0x5B6B7A)
        case .search: return Color(hex: 0x6E7882)
        case .news: return Color(hex: 0xD97706)
        case .bottle: return Color(hex: 0x0997A3)
        }
    }
}

struct StarWorldSystemView: View {
    var embedded = true

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var route: StarWorldRoute?
    @State private var scanPresented = false

    private let content: [StarWorldRoute] = [
        .channels, .live, .games, .music, .look, .shop
    ]
    private let tools: [StarWorldRoute] = [
        .nearby, .miniApps, .search, .news, .bottle
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                List {
                    Section {
                        momentsRow
                    } header: {
                        sectionHeader(Tr("动态"))
                    }

                    Section {
                        ForEach(content) { item in
                            worldRow(item)
                        }
                    } header: {
                        sectionHeader(Tr("内容"))
                    }

                    Section {
                        ForEach(tools) { item in
                            worldRow(item)
                        }
                    } header: {
                        sectionHeader(Tr("工具"))
                    } footer: {
                        Text(Tr("常用内容和服务会依据使用频率自动排序。"))
                            .font(pf(12.5))
                            .foregroundStyle(C.subLabel)
                            .padding(.top, 4)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 52)
                .background(C.pageBg)
            }
            .background(C.pageBg.ignoresSafeArea())
            .navigationDestination(item: $route) { route in
                destination(route)
                    .environmentObject(app)
            }
            .fullScreenCover(isPresented: $scanPresented) {
                ScannerView { text in handleScanned(text, app: app) }
            }
            .toolbar(.hidden, for: .navigationBar)
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

            headerButton("qrcode.viewfinder", label: Tr("扫一扫")) {
                scanPresented = true
            }
            headerButton("magnifyingglass", label: Tr("搜索")) {
                route = .search
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(C.pageBg)
    }

    private func headerButton(
        _ symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(C.label)
                .frame(width: 38, height: 38)
                .background(C.searchBg, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(pf(13, .semibold))
            .foregroundStyle(C.label)
            .textCase(nil)
            .padding(.leading, 2)
    }

    private var momentsRow: some View {
        Button {
            route = .moments
        } label: {
            HStack(spacing: 12) {
                Avatar(
                    path: app.me?.avatarPath ?? "",
                    size: 36,
                    radius: 18,
                    circle: true
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(Tr("生活圈"))
                        .font(pf(16))
                        .foregroundStyle(C.label)
                    Text(app.moments.isEmpty
                         ? Tr("记录此刻，也看看朋友的日常")
                         : Tr("朋友刚刚更新了动态"))
                        .font(pf(12.5))
                        .foregroundStyle(C.subLabel)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(C.time)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func worldRow(_ item: StarWorldRoute) -> some View {
        Button {
            route = item
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.symbol)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        item.tint,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(pf(16))
                        .foregroundStyle(C.label)
                    Text(item.subtitle)
                        .font(pf(11.5))
                        .foregroundStyle(C.subLabel)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(C.time)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        case .shop: MallAuthGate { MallNativeView(app: app) }
        case .nearby: NearbyPageView()
        case .miniApps: MiniAppsView(modal: false)
        case .search: SearchAllView()
        case .news: NewsView(modal: true)
        case .bottle: BottlePageView()
        }
    }
}
