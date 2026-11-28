import SwiftUI
import UniformTypeIdentifiers
import CoreLocation

private struct WorldGroupCard<Content: View>: View {
    let content: Content
    @Environment(\.colorScheme) private var scheme

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    var body: some View {
        content
            .padding(8)
            .background {
                shape.fill(C.cardBg)
            }
            .overlay {
                shape.stroke(
                    scheme == .dark ? C.hairline : Color.black.opacity(0.055),
                    lineWidth: 0.7
                )
            }
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.18 : 0.055),
                    radius: 10, y: 5)
    }
}

private struct WorldSectionHeading: View {
    let title: String
    let count: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(pfStyled(size: 13, weight: .semibold))
                .foregroundStyle(OrbitTheme.secondary)
                .tracking(0.15)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            Text("\(count)")
                .font(pfStyled(size: 9.5, weight: .semibold))
                .foregroundStyle(OrbitTheme.tertiary)
                .frame(minWidth: 19, minHeight: 18)
                .background {
                    Capsule()
                        .fill(OrbitTheme.field.opacity(scheme == .dark ? 0.62 : 0.78))
                }
        }
        .padding(.horizontal, 2)
    }
}

private struct WorldEntryGroup: Identifiable {
    let id: String
    let title: String
    let items: [DiscoverItem]
}

private struct WorldStarfield: View {
    private struct Star {
        let x: Double
        let y: Double
        let radius: Double
        let phase: Double
        let speed: Double
        let baseAlpha: Double
    }

    private let stars: [Star] = (0..<92).map { i in
        let x = Double((i * 47 + 13) % 101) / 101.0
        let y = Double((i * 73 + 29) % 103) / 103.0
        let depth = Double((i * 31 + 7) % 17) / 16.0
        return Star(
            x: x,
            y: y,
            radius: 0.45 + depth * 1.35,
            phase: Double((i * 19) % 31) / 4.4,
            speed: 0.28 + depth * 0.42,
            baseAlpha: 0.22 + depth * 0.54
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for star in stars {
                    let twinkle = 0.5 + 0.5 * sin(time * star.speed + star.phase)
                    let alpha = min(0.92, star.baseAlpha * (0.58 + twinkle * 0.58))
                    let radius = star.radius * (0.90 + twinkle * 0.16)
                    let center = CGPoint(x: star.x * size.width,
                                         y: star.y * size.height)
                    let rect = CGRect(x: center.x - radius,
                                      y: center.y - radius,
                                      width: radius * 2,
                                      height: radius * 2)

                    if star.radius > 1.25 {
                        let glowRect = rect.insetBy(dx: -radius * 5.5,
                                                    dy: -radius * 5.5)
                        context.fill(
                            Path(ellipseIn: glowRect),
                            with: .radialGradient(
                                Gradient(colors: [
                                    Color.white.opacity(alpha * 0.18),
                                    Color.clear
                                ]),
                                center: center,
                                startRadius: 0,
                                endRadius: radius * 6.5
                            )
                        )
                    }

                    context.fill(Path(ellipseIn: rect),
                                 with: .color(Color.white.opacity(alpha)))

                    if star.radius > 1.45 && alpha > 0.48 {
                        var sparkle = Path()
                        sparkle.move(to: CGPoint(x: center.x - radius * 3.2, y: center.y))
                        sparkle.addLine(to: CGPoint(x: center.x + radius * 3.2, y: center.y))
                        sparkle.move(to: CGPoint(x: center.x, y: center.y - radius * 3.2))
                        sparkle.addLine(to: CGPoint(x: center.x, y: center.y + radius * 3.2))
                        context.stroke(sparkle,
                                       with: .color(Color.white.opacity(alpha * 0.20)),
                                       lineWidth: 0.45)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WorldTopIconPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle()
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.06 : 0))
            }
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.92 : 1))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10),
                       value: configuration.isPressed)
    }
}

private enum WorldVisual {
    static let iconSize: CGFloat = 52
    static let iconRadius: CGFloat = 14

    static let social = [
        Color(hex: 0x28B987),
        Color(hex: 0x0E7D62)
    ]
    static let utility = [
        Color(hex: 0x4A9EFF),
        Color(hex: 0x176BD3)
    ]
    static let commerce = [
        Color(hex: 0xE89032),
        Color(hex: 0xB84C16)
    ]
    static let local = [
        Color(hex: 0x25B8B1),
        Color(hex: 0x0D7C82)
    ]
    static let entertainment = [
        Color(hex: 0x7C72F2),
        Color(hex: 0x4E47C8)
    ]
    static let neutral = [
        Color(hex: 0x8A919C),
        Color(hex: 0x59616D)
    ]

    static var topIconInk: Color { Color.dyn(0x3A3A3C, 0xC7C7CC) }
    static var scanInk: Color { social[1] }
    static var chevronInk: Color { Color.dyn(0xA2A2A7, 0x6E6E73) }
    static let originalIconActions: Set<String> = [
        "music", "games", "channels", "look", "miniapps",
        "news", "live", "nearby", "shake", "bottle"
    ]

    static func keepsOriginalIcon(_ action: String?) -> Bool {
        originalIconActions.contains((action ?? "").lowercased())
    }

    static func colors(for color: String?,
                       action: String?,
                       label: String = "") -> [Color] {
        if let raw = color?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            let custom = Color(hexString: raw, fallback: 0x4A90D9)
            return [custom, custom.opacity(0.82)]
        }
        let key = (action ?? "").lowercased()
        let title = label.lowercased()
        if ["shop", "mall", "order", "payment"].contains(where: {
            key == $0 || title.contains($0)
        }) {
            return commerce
        }
        if ["nearby", "map", "shake", "bottle", "live", "local"].contains(where: {
            key == $0 || title.contains($0)
        }) {
            return local
        }
        if ["games", "game", "music", "channels", "video", "works"].contains(where: {
            key == $0 || title.contains($0)
        }) {
            return entertainment
        }
        if ["moments", "favorites", "look", "cards", "friend", "social"].contains(where: {
            key == $0 || title.contains($0)
        }) {
            return social
        }
        if ["settings", "general", "privacy"].contains(where: {
            key == $0 || title.contains($0)
        }) {
            return neutral
        }
        return utility
    }
}

private struct XingyanMallMark: View {
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xEF3541), Color(hex: 0xB40F1A)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color(hex: 0xD51624).opacity(0.30),
                        radius: size * 0.16, y: size * 0.08)

            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.8)

            Ellipse()
                .stroke(Color.white.opacity(0.50), lineWidth: 0.9)
                .frame(width: size * 0.72, height: size * 0.27)
                .rotationEffect(.degrees(-18))

            Image(systemName: "bag.fill")
                .font(.system(size: size * 0.49, weight: .semibold))
                .foregroundStyle(.white)
                .offset(y: size * 0.015)

            Image(systemName: "sparkle")
                .font(.system(size: size * 0.19, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.96))
                .offset(x: size * 0.28, y: -size * 0.26)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct WorldPresentedRoute: Identifiable {
    let key: String
    var id: String { key }
}

struct DiscoverView: View {

    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var lang = LangStore.shared
    @ObservedObject private var musicLibrary = MusicLibrary.shared
    @ObservedObject private var musicPlayer = MusicPlayer.shared
    @EnvironmentObject var app: AppState
    @State private var path = NavigationPath()

    @State private var items: [DiscoverItem] = []
    @State private var loaded = false
    @State private var worldArtwork: [String: String] = [:]

    @State private var showScan = false
    @State private var presentedWorldRoute: WorldPresentedRoute?
    @State private var navScrolled: CGFloat = 0
    @ObservedObject private var realtime = Realtime.shared

    private var latestThumb: String {
        for m in app.moments {
            if let img = m.images?.first, !img.isEmpty { return img }
            if let c = m.videoCover, !c.isEmpty { return c }
        }
        return ""
    }

    private var latestMoment: Moment? {
        app.moments.first
    }

    private var latestMomentAuthor: String {
        if let name = latestMoment?.author?.name, !name.isEmpty { return name }
        if latestMoment?.mine == true, let name = app.me?.name, !name.isEmpty { return name }
        return Tr("生活圈")
    }

    private var latestMomentAvatar: String {
        if let avatar = latestMoment?.author?.avatarPath, !avatar.isEmpty { return avatar }
        if latestMoment?.mine == true { return app.me?.avatarPath ?? "" }
        return ""
    }

    private var latestMomentText: String {
        let text = (latestMoment?.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return String(text.prefix(58)) }
        if latestMoment?.video != nil { return Tr("分享了一段新视频") }
        if latestThumb.isEmpty { return Tr("记录此刻，也看看朋友们的日常") }
        return Tr("分享了一张新照片")
    }

    private var latestMomentMedia: [String] {
        var out: [String] = []
        for moment in app.moments {
            if let image = moment.images?.first, !image.isEmpty, !out.contains(image) {
                out.append(image)
            } else if let cover = moment.videoCover, !cover.isEmpty, !out.contains(cover) {
                out.append(cover)
            }
            if out.count == 3 { break }
        }
        return out
    }

    private var momentCountText: String {
        let count = app.moments.count
        if Lang.isRussian {
            return "\(count) новых публикаций"
        }
        if Lang.isEnglish {
            return "\(count) new \(count == 1 ? "post" : "posts")"
        }
        return "\(count) 条新动态"
    }

    private var heroStatusText: String {
        guard !app.moments.isEmpty else {
            return Tr("记录此刻，也看看朋友们的日常")
        }
        if Lang.isRussian {
            return "\(momentCountText) · Сейчас"
        }
        if Lang.isEnglish {
            return "\(momentCountText) · Happening now"
        }
        return "\(momentCountText) · 此刻正在发生"
    }

    private var discoverTopHeader: some View {
        ZStack {
            Text(Tr("世界"))
                .font(systemTextFont(17, .semibold, relativeTo: .headline))
                .foregroundStyle(OrbitTheme.ink)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity)

            HStack(spacing: 2) {
                Spacer(minLength: 0)

                Button {
                    path.append("search")
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(WorldVisual.topIconInk)
                        .frame(width: 42, height: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(WorldTopIconPressStyle())
                .accessibilityLabel(Tr("搜索"))

                Button {
                    showScan = true
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(WorldVisual.scanInk)
                        .frame(width: 42, height: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(WorldTopIconPressStyle())
                .accessibilityLabel(Tr("扫一扫"))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: discoverHeaderHeight)
    }

    private var discoverHeaderHeight: CGFloat {
        let preferred = 17 * fontScale * CareMode.scale
        let titleHeight = UIFontMetrics(forTextStyle: .headline)
            .scaledValue(for: preferred)
        return max(L.navH, ceil(titleHeight + 12))
    }

    private var worldCanvas: Color {
        UIConfig.colorIfSet("discoverBg") ?? C.discoverBg
    }

    private var worldPageBackground: some View {
        worldCanvas
    }

    private var worldSectionFill: Color {
        C.cardBg
    }

    private var worldRowFill: Color {
        C.cardBg
    }

    private var worldHairline: Color {
        C.hairline
    }

    private func worldSectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(pfStyled(size: 12.5, weight: .semibold))
                .foregroundStyle(OrbitTheme.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 30)
        .background(worldSectionFill)
        .accessibilityAddTraits(.isHeader)
    }

    private func worldUpdatesRow(_ item: DiscoverItem) -> some View {
        Button {
            open(item)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: WorldVisual.social,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 58, height: 58)

                    if !latestThumb.isEmpty {
                        RemoteImage(path: latestThumb, mode: .fill, maxSide: 180)
                            .frame(width: 50, height: 50)
                            .clipShape(Circle())
                    } else {
                        Avatar(path: latestMomentAvatar,
                               size: 50, circle: true)
                    }
                }
                .frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: scheme == .dark ? 4 : 5) {
                    Text(Tr(item.label))
                        .font(pfStyled(size: scheme == .dark ? 16.5 : 17,
                                       weight: .medium))
                        .foregroundStyle(OrbitTheme.ink)
                        .lineLimit(1)
                    Text(heroStatusText)
                        .font(pfStyled(size: scheme == .dark ? 13 : 13.5,
                                       weight: .regular))
                        .foregroundStyle(OrbitTheme.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if !app.moments.isEmpty {
                    Text(app.moments.count > 99 ? "99+" : "\(app.moments.count)")
                        .font(pfStyled(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, app.moments.count > 9 ? 6 : 0)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Capsule().fill(WorldVisual.social[1]))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 72)
            .background(worldRowFill)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuPressStyle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(worldHairline)
                .frame(height: 0.5)
                .padding(.leading, 88)
        }
        .accessibilityElement(children: .combine)
    }

    private func worldFlatRow(_ item: DiscoverItem) -> some View {
        let colors = WorldVisual.colors(
            for: item.color,
            action: item.action,
            label: item.label
        )
        let keepsOriginalIcon = WorldVisual.keepsOriginalIcon(item.action)
        let artwork = worldArtworkPath(item)

        return Button {
            open(item)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    if keepsOriginalIcon {
                        RoundedRectangle(cornerRadius: WorldVisual.iconRadius,
                                         style: .continuous)
                            .fill(colors[0])
                    } else {
                        RoundedRectangle(cornerRadius: WorldVisual.iconRadius,
                                         style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: colors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        RoundedRectangle(cornerRadius: WorldVisual.iconRadius,
                                         style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.18), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }

                    if !artwork.isEmpty {
                        RemoteImage(path: artwork, mode: .fill, maxSide: 180)
                            .frame(width: WorldVisual.iconSize,
                                   height: WorldVisual.iconSize)
                            .clipShape(RoundedRectangle(cornerRadius: WorldVisual.iconRadius,
                                                       style: .continuous))
                    } else {
                        Image(systemName: RowIcon.sf(action: item.action,
                                                     label: item.label))
                            .font(.system(size: keepsOriginalIcon ? 21 : 20,
                                          weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: keepsOriginalIcon
                                    ? .clear
                                    : Color.black.opacity(0.16),
                                    radius: keepsOriginalIcon ? 0 : 0.8,
                                    y: keepsOriginalIcon ? 0 : 0.6)
                    }

                    if !keepsOriginalIcon {
                        RoundedRectangle(cornerRadius: WorldVisual.iconRadius,
                                         style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
                    }
                }
                .frame(width: WorldVisual.iconSize,
                       height: WorldVisual.iconSize)
                .shadow(color: keepsOriginalIcon
                        ? .clear
                        : colors[1].opacity(0.18),
                        radius: keepsOriginalIcon ? 0 : 4.5,
                        y: keepsOriginalIcon ? 0 : 2)

                VStack(alignment: .leading, spacing: scheme == .dark ? 3 : 4) {
                    Text(Tr(item.label))
                        .font(pfStyled(size: 16.5,
                                       weight: .medium))
                        .foregroundStyle(OrbitTheme.ink)
                        .lineLimit(1)
                    Text(worldSubtitle(item))
                        .font(pfStyled(size: scheme == .dark ? 13.5 : 13,
                                       weight: .regular))
                        .foregroundStyle(OrbitTheme.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WorldVisual.chevronInk)
            }
            .padding(.horizontal, 16)
            .frame(height: 64)
            .background(worldRowFill)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuPressStyle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(worldHairline)
                .frame(height: 0.5)
                .padding(.leading, 80)
        }
        .accessibilityElement(children: .combine)
    }

    private func worldShopRow(_ item: DiscoverItem) -> some View {
        Button {
            open(item)
        } label: {
            HStack(spacing: 12) {
                XingyanMallMark(size: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text(Tr("星选商城"))
                        .font(pfStyled(size: 16.5, weight: .medium))
                        .foregroundStyle(OrbitTheme.ink)
                    Text(Tr("今日精选 · 每日上新"))
                        .font(pfStyled(size: 13, weight: .regular))
                        .foregroundStyle(OrbitTheme.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WorldVisual.chevronInk)
            }
            .padding(.horizontal, 16)
            .frame(height: 64)
            .background(worldRowFill)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuPressStyle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(worldHairline)
                .frame(height: 0.5)
                .padding(.leading, 80)
        }
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Color.clear.frame(height: discoverHeaderHeight)

                        if let hero = worldHeroItem {
                            worldSectionHeader(Tr("动态"))
                            worldUpdatesRow(hero)
                            Color.clear.frame(height: 8)
                        }

                        if worldShopItem != nil || !worldEntryGroups.isEmpty {
                            worldSectionHeader(Tr("探索"))

                            if let shop = worldShopItem {
                                worldShopRow(shop)
                                Color.clear.frame(height: 8)
                            }

                            ForEach(worldEntryGroups) { group in
                                worldSectionHeader(group.title)
                                VStack(spacing: 0) {
                                    ForEach(group.items) { item in
                                        worldFlatRow(item)
                                    }
                                }
                                Color.clear.frame(height: 8)
                            }
                        }

                        Color.clear
                            .frame(height: max(24, L.safeBottom + L.tabH + 12))
                    }
                    .background {
                        NativeTopScrollObserver { y in
                            let next: CGFloat = y > 8 ? 1 : 0
                            if navScrolled != next { navScrolled = next }
                        } onScrollViewReady: { scroll in
                            NativeTopScrollRegistry.shared.discover = scroll
                        }
                    }
                }

                .background(Color.clear)

                discoverTopHeader
                    .measure("discover.nav")
                    .background {
                        ZStack {
                            NativeTopGlassMask(active: navScrolled > 0,
                                               base: worldCanvas)
                            if #available(iOS 26.0, *) {
                                NativeScrollEdgeElementBridge(
                                    scrollView: { NativeTopScrollRegistry.shared.discover }
                                )
                            }
                        }
                        .ignoresSafeArea(edges: .top)
                    }
                    .contentShape(Rectangle())
                    .zIndex(10)
            }
            .background(worldPageBackground.ignoresSafeArea(edges: .bottom))

            .background(worldPageBackground.ignoresSafeArea(edges: .top))
            .toolbar(.hidden, for: .navigationBar)
            .overlay {
                if app.offline && path.isEmpty {
                    worldOfflineView
                        .transition(.opacity)
                }
            }
            .systemAnimation(.easeInOut(duration: 0.2), value: app.offline)
            .navigationDestination(for: String.self) { key in
                if key == "moments" {
                    MomentsView()
                } else if key == "nearby" {
                    NearbyPageView()
        } else if key == "shake" {

            BottlePageView()
        } else if key == "bottle" {

            BottlePageView()
                } else if key == "live" {
                    LiveListView()
                } else if key == "games" {
                    GamesPageView()
                } else if key == "channels" {
                    ChannelsView()
                } else if key == "look" {
                    LookView()
                } else if key == "search" {
                    SearchAllView()
                } else if key == "news" {
                    NewsView()
                } else if key == "music" {

                    ListenView(onLeave: {
                        DispatchQueue.main.async {
                            path = NavigationPath()
                        }
                    })
                } else if key == "miniapps" {

                    MiniAppsView()
                } else if key == "shop" || key == "mall" {
                    MallAuthGate { MallNativeView(app: app) }
                        .environmentObject(app)
                } else if key.hasPrefix("soon:") {
                    ComingSoonView(title: String(key.dropFirst(5)))
                } else {
                    ComingSoonView(title: key)
                }
            }
        }

        .onChange(of: realtime.event) { ev in
            if ev.type == "moment" || ev.user != nil { Task { await app.loadMoments() } }
            if ev.type == "ui" { Task { await loadItems() } }
        }

        .onReceive(NotificationCenter.default.publisher(for: .chrisUIPrefsChanged)) { _ in
            Task { await loadItems() }
        }
        .onChange(of: app.offline) { off in
            if !off { Task { await loadItems() } }
        }
        .task {
            if !loaded { await loadItems() }
            if worldArtwork.isEmpty { await loadWorldArtwork() }
        }
        .fullScreenCover(isPresented: $showScan) {
            ScannerView { text in handleScanned(text, app: app) }
        }
        .fullScreenCover(item: $presentedWorldRoute) { route in
            if route.key == "music" {
                ListenView(onLeave: {
                    presentedWorldRoute = nil
                })
                .environmentObject(app)
            } else {
                NavigationStack {
                    worldDestination(route.key)
                        .environmentObject(app)
                }
            }
        }
    }

    private var worldOfflineView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(OrbitTheme.secondary)
                .frame(width: 72, height: 72)
                .background(Color.primary.opacity(0.045), in: Circle())

            VStack(spacing: 6) {
                Text(Tr("世界暂时离线"))
                    .font(pfStyled(size: 20, weight: .semibold))
                    .foregroundStyle(OrbitTheme.ink)
                Text(Tr("连接恢复后会自动刷新，旧页面不会继续显示。"))
                    .font(pfStyled(size: 13))
                    .foregroundStyle(OrbitTheme.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await app.checkReachability() }
            } label: {
                Text(Tr("重新加载"))
                    .font(pfStyled(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .frame(height: 42)
                    .background(WorldVisual.social[1], in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 34)
        .background(worldCanvas.ignoresSafeArea())
    }

    private var grouped: [[DiscoverItem]] {

        let source = effectiveItems
        let visible = MomentsPref.isOn ? source : source.filter { $0.action != "moments" }
        var out: [[DiscoverItem]] = []
        var last: Int? = nil
        for it in visible {
            let g = it.group ?? 1
            if last == nil || g != last! { out.append([]); last = g }
            out[out.count - 1].append(it)
        }
        return out
    }

    private var effectiveItems: [DiscoverItem] {
        var list = items
        let mall = DiscoverItem(id: "d11", label: "商城", icon: "i.shop",
                                svg: I.wallet, color: "#E02A0F", action: "shop",
                                group: 6, enabled: true)
        if let index = list.firstIndex(where: { $0.action == "shop" || $0.action == "mall" }) {
            list[index] = mall
        } else {
            list.append(mall)
        }
        if !list.contains(where: { $0.action == "miniapps" }) {
            list.insert(
                DiscoverItem(id: "d12", label: "小程序", icon: "i.miniapps",
                             svg: "", color: "#239B68", action: "miniapps",
                             group: 1, enabled: true),
                at: 0
            )
        }
        return list
    }

    private var visibleWorldItems: [DiscoverItem] {
        grouped.flatMap { $0 }.filter { $0.action != "map" }
    }

    private var worldShopItem: DiscoverItem? {
        visibleWorldItems.first { $0.action == "shop" || $0.action == "mall" }
    }

    private var worldHeroItem: DiscoverItem? {
        visibleWorldItems.first { $0.action == "moments" }
    }

    private var worldGridItems: [DiscoverItem] {
        visibleWorldItems.filter {
            $0.action != "shop" && $0.action != "mall" && $0.action != "moments"
        }
    }

    private var worldColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private var worldEntryGroups: [WorldEntryGroup] {
        let rules: [(id: String, title: String, actions: Set<String>)] = [
            ("content", Tr("内容与现场"),
             ["channels", "live", "music", "games"]),
            ("discover", Tr("发现"),
             ["nearby", "bottle", "shake", "look", "search"]),
            ("tools", Tr("工具与效率"),
             ["scan", "miniapps"])
        ]
        var used: Set<String> = []
        var groups: [WorldEntryGroup] = []
        for rule in rules {
            let entries = worldGridItems.filter {
                rule.actions.contains($0.action ?? "")
            }
            if !entries.isEmpty {
                used.formUnion(entries.map(\.id))
                groups.append(WorldEntryGroup(id: rule.id,
                                              title: rule.title,
                                              items: entries))
            }
        }
        let remaining = worldGridItems.filter { !used.contains($0.id) }
        if !remaining.isEmpty {
            groups.append(WorldEntryGroup(id: "more",
                                          title: Tr("更多"),
                                          items: remaining))
        }
        return groups
    }

    private func worldSubtitle(_ item: DiscoverItem) -> String {
        switch item.action ?? "" {
        case "moments": return Tr("好友动态与日常分享")
        case "channels": return Tr("短视频与创作者内容")
        case "live": return Tr("正在直播与热门房间")
        case "scan": return Tr("扫描二维码与条形码")
        case "map": return Tr("星轨地图与导航")
        case "bottle", "shake": return Tr("随机遇见有趣的人")
        case "look": return Tr("发现值得阅读的内容")
        case "search": return Tr("搜人、消息与世界内容")
        case "nearby": return Tr("附近的人与同城动态")
        case "games": return Tr("小游戏与好友排行榜")
        case "music": return Tr("听歌、歌单与音乐分享")
        case "miniapps": return Tr("常用工具与轻量服务")
        default: return Tr("打开这个功能入口")
        }
    }

    private func worldArtworkPath(_ item: DiscoverItem) -> String {
        switch item.action ?? "" {
        case "music":
            let recent = musicLibrary.recents.first?.cover ?? ""
            if !recent.isEmpty { return recent }
            return musicPlayer.current?.cover ?? worldArtwork["music"] ?? ""
        case "channels":
            return latestThumb.isEmpty ? (worldArtwork["channels"] ?? "") : latestThumb
        default:
            return worldArtwork[item.action ?? ""] ?? ""
        }
    }

    private func loadWorldArtwork() async {
        async let appRequest = API.shared.miniApps()
        async let musicRequest = API.shared.musicTracks()
        let apps = await appRequest
        let tracks = await musicRequest
        var artwork: [String: String] = [:]
        if let cover = apps.first(where: {
            !$0.isGame && !($0.cover ?? "").isEmpty
        })?.cover {
            artwork["miniapps"] = cover
        }
        if let cover = apps.first(where: {
            $0.isGame && !($0.cover ?? "").isEmpty
        })?.cover {
            artwork["games"] = cover
        }
        if let cover = tracks.first(where: { !($0.cover ?? "").isEmpty })?.cover {
            artwork["music"] = cover
        }
        worldArtwork = artwork
    }

    private func worldFeatureCard(_ item: DiscoverItem) -> some View {
        Button {
            open(item)
        } label: {
            ZStack(alignment: .bottomLeading) {
                if latestThumb.isEmpty {
                    LinearGradient(
                        colors: [Color(hex: 0x10271F), Color(hex: 0x275F4E), Color(hex: 0x0F1B17)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    RemoteImage(path: latestThumb, mode: .fill, maxSide: 900)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.05), location: 0),
                        .init(color: .black.opacity(0.18), location: 0.38),
                        .init(color: .black.opacity(0.88), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                    .frame(width: 230, height: 230)
                    .offset(x: 220, y: -104)
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
                    .frame(width: 150, height: 150)
                    .offset(x: 272, y: 52)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        HStack(spacing: 7) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12, weight: .semibold))
                            Text(Tr(item.label))
                                .font(pfStyled(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.94))
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .background(C.floatingSurface, in: Capsule())

                        if app.showDot("momentsRow", auto: !latestThumb.isEmpty) {
                            Circle()
                                .fill(Color(hex: 0xFF5A52))
                                .frame(width: 7, height: 7)
                        }

                        Spacer(minLength: 6)

                        Text(momentCountText)
                            .font(pfStyled(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.86))
                            .padding(.horizontal, 10)
                            .frame(height: 27)
                            .background(Color.black.opacity(0.22), in: Capsule())
                    }

                    Spacer(minLength: 24)

                    HStack(alignment: .bottom, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Tr("生活圈"))
                                .font(pfStyled(size: 25, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.25), radius: 7, y: 3)

                            HStack(spacing: 8) {
                                Avatar(path: latestMomentAvatar,
                                       size: 26, radius: 13, circle: true)
                                    .overlay(Circle().stroke(Color.white.opacity(0.72),
                                                             lineWidth: 1))
                                Text(latestMomentAuthor)
                                    .font(pfStyled(size: 11.5, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.84))
                                    .lineLimit(1)
                            }

                            Text(latestMomentText)
                                .font(pfStyled(size: 12.5, weight: .regular))
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(2)
                                .lineSpacing(2)
                        }

                        Spacer(minLength: 4)

                        if latestMomentMedia.count > 1 {
                            HStack(spacing: -12) {
                                ForEach(Array(latestMomentMedia.dropFirst().enumerated()),
                                        id: \.offset) { index, media in
                                    RemoteImage(path: media, mode: .fill, maxSide: 260)
                                        .frame(width: 62, height: 76)
                                        .clipShape(RoundedRectangle(cornerRadius: 12,
                                                                    style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(Color.white.opacity(0.28), lineWidth: 0.8)
                                        }
                                        .rotationEffect(.degrees(index == 0 ? -4 : 4))
                                        .shadow(color: .black.opacity(0.20), radius: 8, y: 4)
                                }
                            }
                            .padding(.trailing, 4)
                        }
                    }

                    HStack(spacing: 7) {
                        Text(Tr("打开生活圈"))
                            .font(pfStyled(size: 11.5, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10.5, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 31)
                    .background(OrbitTheme.jade.opacity(0.92), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.7))
                    .padding(.top, 14)
                }
                    .padding(18)
            }
            .frame(height: 232)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.13), lineWidth: 0.8)
            }
            .shadow(color: Color(hex: 0x14231D).opacity(0.20), radius: 18, y: 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuPressStyle())
        .accessibilityElement(children: .combine)
    }

    private func worldEntryCard(_ item: DiscoverItem) -> some View {
        let accent = Color(hexString: item.color ?? "#4A90D9", fallback: 0x4A90D9)
        let artwork = worldArtworkPath(item)
        return Button {
            open(item)
        } label: {
            ZStack(alignment: .bottomLeading) {
                if artwork.isEmpty {
                    LinearGradient(
                        colors: [
                            accent.opacity(0.96),
                            accent.opacity(0.78),
                            Color(hex: 0x17201C)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    RemoteImage(path: artwork, mode: .fill, maxSide: 720)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }

                LinearGradient(
                    colors: [
                        Color.black.opacity(artwork.isEmpty ? 0.02 : 0.05),
                        Color.black.opacity(artwork.isEmpty ? 0.08 : 0.25),
                        Color.black.opacity(artwork.isEmpty ? 0.42 : 0.68)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(artwork.isEmpty ? 0.18 : 0.20))
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.20), lineWidth: 0.7)
                            Image(systemName: RowIcon.sf(action: item.action, label: item.label))
                                .font(.system(size: 18.5, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 42, height: 42)

                        Spacer(minLength: 6)

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 27, height: 27)
                            .background(Circle().fill(Color.white.opacity(0.16)))
                            .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 0.7))
                    }

                    Spacer(minLength: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(Tr(item.label))
                            .font(pfStyled(size: 16.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(worldSubtitle(item))
                            .font(pfStyled(size: 11.5, weight: .regular))
                            .foregroundStyle(.white.opacity(0.74))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                    .padding(14)
            }
            .frame(maxWidth: .infinity, minHeight: 148, maxHeight: 148)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.7)
            }
            .shadow(color: accent.opacity(0.10), radius: 10, y: 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuPressStyle())
        .accessibilityElement(children: .combine)
    }

    private func worldShopCard(_ item: DiscoverItem) -> some View {
        Button {
            open(item)
        } label: {
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: [Color(hex: 0xA51612), Color(hex: 0xD72A20)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color.white.opacity(0.055))
                    .frame(width: 156, height: 156)
                    .offset(x: 230, y: -54)
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    .frame(width: 104, height: 104)
                    .offset(x: 264, y: 44)

                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(Color.white.opacity(0.13), lineWidth: 0.7)
                        Image(systemName: "bag.fill")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Text(Tr("星选商城"))
                                .font(pfStyled(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(Tr("今日精选"))
                                .font(pfStyled(size: 9.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                                .padding(.horizontal, 7)
                                .frame(height: 20)
                                .background(Capsule().fill(Color.white.opacity(0.13)))
                        }
                        Text(Tr("自营与第三方好物 · 每日上新"))
                            .font(pfStyled(size: 11.5))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.13)))
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.7))
                }
                    .padding(.horizontal, 16)
            }
            .frame(height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuPressStyle())
        .accessibilityElement(children: .combine)
    }

    private func loadItems() async {
        if items.isEmpty {
            items = DiscoverItem.builtin
            loaded = true
        }
        if let cached = FeatureManifestStore.cachedItems(),
           !cached.isEmpty {
            items = cached
            loaded = true
        }
        if let data = try? await API.shared.signedFeatureManifest(),
           let list = try? FeatureManifestStore.verifyAndCache(data),
           !list.isEmpty {
            items = list
            loaded = true
        } else if let list = try? await API.shared.discover(),
                  !list.isEmpty {
            items = list
            loaded = true
        } else if items.isEmpty {
            items = DiscoverItem.builtin
            loaded = true
        }
    }

    private func open(_ item: DiscoverItem) {
        let action = item.action ?? "soon"
        let label = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["listen", "听一听", "听音乐", "音乐"].contains(action)
            || label == "听一听" || label == "听音乐" {
            presentedWorldRoute = WorldPresentedRoute(key: "music")
            return
        }
        switch action {
        case "scan":
            showScan = true
        case "mall":
            presentedWorldRoute = WorldPresentedRoute(key: "shop")
        case "soon":
            presentedWorldRoute = WorldPresentedRoute(key: "soon:" + item.label)
        default:
            presentedWorldRoute = WorldPresentedRoute(key: action)
        }
    }

    @ViewBuilder
    private func worldDestination(_ key: String) -> some View {
        switch key {
        case "moments": MomentsView()
        case "map": ComingSoonView(title: Tr("星轨地图"))
        case "nearby": NearbyPageView()
        case "shake", "bottle": BottlePageView()
        case "live": LiveListView()
        case "games": GamesPageView()
        case "channels": ChannelsView()
        case "look": LookView()
        case "search": SearchAllView()
        case "news": NewsView(modal: true)
        case "music":
            ListenView(onLeave: {
                presentedWorldRoute = nil
            })
        case "miniapps": MiniAppsView(modal: true)
        case "shop": MallAuthGate { MallNativeView(app: app) }
        default: ComingSoonView(title: String(key.dropFirst(5)))
        }
    }

    private var gap: some View {
        Rectangle().fill(C.pageBg).frame(height: L.groupGap)
    }

    private var rowLine: some View {
        Rectangle()
            .fill(OrbitTheme.divider)
            .frame(height: 0.5)
            .padding(.leading, L.menuLineInset)
    }
}

private struct SystemComposerPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.58 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.08),
                value: configuration.isPressed
            )
    }
}

extension DiscoverItem {
    static var builtin: [DiscoverItem] {
        [
            DiscoverItem(id: "d01", label: "生活圈", icon: "i.moments", svg: I.moments,
                         color: "#4A90D9", action: "moments", group: 1, enabled: true),
            DiscoverItem(id: "d12", label: "小程序", icon: "i.miniapps", svg: "",
                         color: "#239B68", action: "miniapps", group: 1, enabled: true),
            DiscoverItem(id: "d02", label: "视频号", icon: "i.channels", svg: I.channels,
                         color: "#F2943B", action: "channels", group: 2, enabled: true),
            DiscoverItem(id: "d03", label: "直播", icon: "i.live", svg: I.live,
                         color: "#F4525B", action: "live", group: 2, enabled: true),
            DiscoverItem(id: "d04", label: "扫一扫", icon: "i.scan", svg: I.scan,
                         color: "#3D83E7", action: "scan", group: 3, enabled: true),

            DiscoverItem(id: "d05", label: "漂流瓶", icon: "i.shake", svg: I.shake,
                         color: "#2E7BD6", action: "bottle", group: 3, enabled: true),
            DiscoverItem(id: "d06", label: "看一看", icon: "i.look", svg: I.look,
                         color: "#7275E9", action: "look", group: 4, enabled: true),
            DiscoverItem(id: "d07", label: "搜一搜", icon: "i.searchRow", svg: I.searchRow,
                         color: "#59C47E", action: "search", group: 4, enabled: true),
            DiscoverItem(id: "d08", label: "附近", icon: "i.nearby", svg: I.nearby,
                         color: "#3D83E7", action: "nearby", group: 5, enabled: true),
            DiscoverItem(id: "d10", label: "游戏", icon: "i.game", svg: I.game,
                         color: "#9A6AE8", action: "games", group: 7, enabled: true),
            DiscoverItem(id: "d11", label: "商城", icon: "i.shop", svg: I.wallet,
                         color: "#E02A0F", action: "shop", group: 6, enabled: true)
        ]
    }

    static var builtinMe: [DiscoverItem] {
        [
            DiscoverItem(id: "m01", label: "服务", icon: "i.wallet", svg: I.wallet,
                         color: "#59C47E", action: "service", group: 1, enabled: true),
            DiscoverItem(id: "m02", label: "收藏", icon: "i.star", svg: I.star,
                         color: "#4489EA", action: "favorites", group: 2, enabled: true),

            DiscoverItem(id: "m07", label: "小店与卡包", icon: "i.wallet", svg: I.wallet,
                         color: "#E08A22", action: "shop", group: 2, enabled: true),
            DiscoverItem(id: "m03", label: "生活圈", icon: "i.album", svg: I.album,
                         color: "#7275E9", action: "moments", group: 2, enabled: true),
            DiscoverItem(id: "m04", label: "作品", icon: "i.works", svg: I.works,
                         color: "#3D83E7", action: "works", group: 2, enabled: true),
            DiscoverItem(id: "m05", label: "表情", icon: "i.sticker", svg: I.sticker,
                         color: "#F5C144", action: "stickers", group: 3, enabled: true),
            DiscoverItem(id: "m06", label: "设置", icon: "i.gear", svg: I.gear,
                         color: "#3D83E7", action: "settings", group: 4, enabled: true)
        ]
    }
}

struct ComingSoonView: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Text(title).font(pf(17)).foregroundColor(C.label)
            Text(Tr("这一页排在下一批")).font(pf(14)).foregroundColor(C.subLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(C.pageBg)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(pf(18, .medium))
                }
            }
            ToolbarItem(placement: .principal) {
                Text(title).font(pf(UIConfig.num("navTitle", 17))).foregroundColor(C.label)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .swipeBack { dismiss() }
        .hidesTabBar()
    }
}

private final class MomentCoverPullBox {
    var value: CGFloat = 0
}

private final class MomentDragClock {
    var lastDragAt = Date(timeIntervalSince1970: 0)
}

struct MomentsView: View {
    private static let momentPageSize = 70
    private static let stressMomentWindow = 120
    private static let stressMomentPageSize = 20
    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()
    private static let yearMonthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()

    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var target: User? = nil

    var mineOnly: Bool = false

    private var feedUserId: String? { mineOnly ? app.me?.id : target?.id }

    private var coverEditable: Bool { target == nil || mineOnly }

    @State private var sentinelGone = false

    @State private var solid = false
    @State private var momentsScrollActive = false
    @State private var moments: [Moment] = []
    @State private var stressLoadedMoments: [Moment] = []
    @State private var momentFeedRevision = 0
    @State private var locallyPostedMoments: [String: Moment] = [:]
    @State private var stressLoadedCount = min(MomentStressFixture.count,
                                               Self.stressMomentWindow)
    @State private var prefetchedMoments: [Moment] = []
    @State private var prefetchedHasMore = false
    @State private var prefetchingMoments = false
    @State private var locallyDeletedMomentIds: Set<String> = []
    @State private var momentPrefetchTask: Task<Void, Never>?

    @State private var confirmDiscard = false
    @State private var showPhoto = false
    @State private var showCamera = false

    @State private var showVideoShoot = false
    @State private var showCoverPhoto = false

    @State private var coverMenu = false
    @State private var showCoverCamera = false
    @State private var coverDraft: UIImage?

    @State private var coverLocked = false
    @State private var coverLockPull: CGFloat = 0
    @State private var coverOverride = ""
    @State private var coverPreview: UIImage?

    @State private var coverPullBox = MomentCoverPullBox()
    @State private var composerPick = false

    @State private var composerVideoPick = false
    @State private var pickMediaMenu = false

    @State private var showMomentAlbum = false
    @State private var pickedVideo: URL?
    @State private var videoCover: UIImage?
    @State private var videoSeconds = 0
    @State private var videoWH: (w: Int, h: Int)?
    @State private var videoProgress = 0.0
    @State private var publishProgress = 0.0
    @State private var publishStatus = ""
    @State private var posting = false
    @State private var draft = ""
    @State private var picked: [UIImage] = []
    @State private var uploading = false
    @State private var publishError = ""
    @State private var commentsSheet: Moment?
    @State private var likesSnapshot: [MomentLike] = []
    @State private var showLikes = false

    @State private var actionMoment: Moment?
    @State private var pendingDeleteMoment: Moment?

    @State private var viewerPaths: [String] = []
    @State private var viewerIndex: Int?

    @State private var momentVideo: URL?

    @State private var cardUser: User?
    @State private var liveTarget: User?

    @State private var hasMoreMoments = false

    @State private var feedRange = "all"

    @State private var visibility = "public"
    @State private var showVisibility = false
    @State private var showPick = false
    @State private var pickMode = "partial"
    @State private var visibleTo: Set<String> = []
    @State private var hiddenFrom: Set<String> = []

    @State private var draftLocation = ""
    @State private var remindIds: Set<String> = []
    @State private var showLocation = false

    @State private var dragIndex: Int?

    @State private var tapLockUntil = Date(timeIntervalSince1970: 0)
    @State private var lastRouteOpenAt = Date.distantPast
    @State private var loadingMore = false
    @State private var momentTotal = 0

    @State private var pullY: CGFloat = 0
    @State private var pulling = false
    @State private var spin: Double = 0
    @State private var spinTask: Task<Void, Never>?

    @State private var dragClock = MomentDragClock()
    @State private var scrollGateActive = false
    @ObservedObject private var realtime = Realtime.shared
    @State private var expandedGroups: Set<String> = []

    @State private var foldRowsCache: [FoldRow] = []

    @State private var groupPage: MomentGroup?
    @State private var showGroupPage = false

    @State private var showNoticeList = false

    private var owner: User? {
        if let target {
            return liveTarget ?? app.contact(for: target.id) ?? target
        }
        return app.me
    }
    private var cover: String {
        if coverEditable, !coverOverride.isEmpty { return coverOverride }
        return owner?.momentCover ?? ""
    }

    private var coverOverrideKey: String {
        "chris.momentCover.override." + (app.me?.id ?? "")
    }

    private var signature: String? {
        let s = (owner?.bio ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private var momentProfileFooterHeight: CGFloat {
        max(38, L.coverAvatar * 0.56)
    }

    var body: some View {
        ZStack(alignment: .top) {

            C.pageBg.ignoresSafeArea()

            NativeMomentFeed(
                moments: displayedMoments,
                revision: momentFeedRevision,
                dark: scheme == .dark,
                mineOnly: mineOnly,
                dayKey: "\(Lang.code)-\(scheme)-\(app.contacts.count)",
                headerHeight: L.coverH + momentProfileFooterHeight
                    + (coverLocked ? coverLockPull : 0),
                collapseOffset: L.coverH - 52,
                onScrollActive: { active in
                    guard momentsScrollActive != active else { return }
                    withSystemAnimation(.easeOut(duration: active ? 0.12 : 0.20)) {
                        momentsScrollActive = active
                    }
                    if active {
                        guard !scrollGateActive else { return }
                        scrollGateActive = true
                        ScrollGate.shared.setScrolling(true)
                    } else {
                        tapLockUntil = Date().addingTimeInterval(0.35)
                        guard scrollGateActive else { return }
                        scrollGateActive = false
                        ScrollGate.shared.setScrolling(false)
                    }
                },
                onCollapseChange: { collapsed in
                    if solid != collapsed { solid = collapsed }
                    if sentinelGone != collapsed { sentinelGone = collapsed }
                },
                onPullChange: { pull in
                    guard !sentinelGone, !pulling else { return }
                    let next = min(140, max(0, pull))
                    guard abs(next - pullY) >= 2 else { return }
                    dragClock.lastDragAt = Date()
                    pullY = next
                    spin = Double(next) * 3.2
                },
                onPullEnd: { pull in
                    dragClock.lastDragAt = Date()
                    if pull > 60 && !pulling {
                        startPullRefresh()
                    } else if !pulling {
                        pullY = 0
                    }
                },
                onApproachingEnd: {
                    Task { await loadMoreMoments() }
                },
                actions: nativeMomentActions,
                stressText: momentStressStatus,
                footerText: momentFooterText,
                footerWaiting: loadingMore,
                dayLabel: { moment in
                    mineOnly
                        ? fullDateLabel(moment.createdAt)
                        : dayLabel(moment.createdAt)
                },
                header: { extra in
                    coverView(coverLocked ? coverLockPull : extra)
                }
            )
            .background(C.pageBg)
            .ignoresSafeArea(edges: .top)

            .task(id: pullY > 0 || pulling) {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if Task.isCancelled { return }
                    if pulling {

                        if Date().timeIntervalSince(dragClock.lastDragAt) > 10 {
                            CrashCatcher.note("朋友圈", "下拉刷新超过 10 秒没回来，先收球")
                            pulling = false
                            pullY = 0
                            spin = 0
                        }
                        continue
                    }
                    if pullY > 0 && Date().timeIntervalSince(dragClock.lastDragAt) > 0.4 {
                        pullY = 0
                        spin = 0
                        return
                    }
                    if pullY <= 0 { return }
                }
            }

            navBar

            if pullY > 0 || pulling {
                ColorBall(size: 34, spin: spin)
                    .scaleEffect(0.72 + min(1, pullY / 90) * 0.28)
                    .offset(y: min(96, pullY * 0.8) + L.safeTop + 6)
                    .systemAnimation(.easeOut(duration: 0.12), value: pullY)
                    .allowsHitTesting(false)
                    .zIndex(30)
            }

            if let i = viewerIndex, !viewerPaths.isEmpty {

                PhotoPager(paths: viewerPaths, startIndex: i, showActions: true) {
                    viewerIndex = nil
                    tapLockUntil = Date().addingTimeInterval(0.6)
                }
                    .zIndex(40)
            }

        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()

        .navigationDestination(isPresented: $showGroupPage) {
            if let g = groupPage {
                MomentGroupPage(title: g.title, moments: g.moments, onDeleted: {
                    Task {
                        await reload()
                        await app.loadMoments()
                    }
                })
            }
        }

        .navigationDestination(isPresented: $showNoticeList) {
            MomentNoticesView(onOpen: { n in openNotice(n) })
                .environmentObject(app)
        }
        .modifier(TapAvatarCard(cardUser: $cardUser))
        .hidesTabBar()

        .sheet(isPresented: Binding(get: { momentVideo != nil },
                                    set: { if !$0 { momentVideo = nil } })) {
            if let u = momentVideo { VideoPlayerSheet(url: u) }
        }
        .sheet(item: $commentsSheet) { moment in
            MomentCommentsSheet(moment: moment) {
                Task { await reload() }
            }
            .environmentObject(app)
            .presentationDetents([.fraction(0.72), .large])
            .presentationDragIndicator(.hidden)
        }
        .modifier(MomentLikesPresenter(likes: likesSnapshot,
                                       isPresented: $showLikes))
        .onAppear {
            sentinelGone = false
            solid = false
            momentsScrollActive = false
            coverOverride = UserDefaults.standard.string(forKey: coverOverrideKey) ?? ""
            if !coverOverride.isEmpty, !coverOverride.hasPrefix("local-"),
               coverOverride != (owner?.momentCover ?? "") {
                clearCoverOverride()
            }
        }
        .onDisappear {
            momentPrefetchTask?.cancel()
            momentsScrollActive = false
            guard scrollGateActive else { return }
            scrollGateActive = false
            ScrollGate.shared.setScrolling(false)
        }
        .onChange(of: owner?.momentCover) { remote in
            guard coverEditable, !coverOverride.isEmpty,
                  !coverOverride.hasPrefix("local-") else { return }
            if coverOverride != (remote ?? "") {
                clearCoverOverride()
            }
        }
        .task {

            if moments.isEmpty, target == nil, !mineOnly {
                let cached = LocalStore.cachedMoments(userId: app.me?.id ?? "")
                if !cached.isEmpty {
                    let page = Array(cached.prefix(Self.momentPageSize))
                    setMomentsWithoutAnimation(page)
                }
            }
            await reload()
        }

        .onChange(of: realtime.event) { event in
            if event.type == "profile", let user = event.user,
               user.id == target?.id {
                liveTarget = user
            }

            let t = event.type.lowercased()
            guard t.contains("moment") || t.contains("like") || t.contains("comment") else { return }
            if event.type == "moment", event.action == "delete", !event.momentId.isEmpty {
                forgetMomentLocally(event.momentId)
            }
            Task { await pollNewMoments() }
        }
        .task {
            if liveTarget == nil { liveTarget = target }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if Task.isCancelled { break }
                await pollNewMoments()
            }
        }

        .confirmationDialog(Tr("更换相册封面"), isPresented: $coverMenu, titleVisibility: .visible) {
            Button(Tr("从手机相册选择")) { showCoverPhoto = true }
            Button(Tr("拍一张")) { showCoverCamera = true }
            Button(Tr("取消"), role: .cancel) { }
        }
        .sheet(isPresented: $showCoverCamera) {
            CameraPicker { image in coverDraft = image }
        }

        .sheet(isPresented: Binding(get: { coverDraft != nil },
                                    set: { if !$0 { coverDraft = nil } })) {
            if let img = coverDraft {
                CoverAdjustSheet(image: img,
                                 frameSize: CGSize(width: L.width, height: L.coverH)) { out in
                    changeCover(out)
                    coverDraft = nil
                }
            }
        }

        .sheet(isPresented: $showVideoShoot, onDismiss: { showVideoShoot = false }) {
            CameraVideoPicker { url in
                Task {
                    await prepareVideo(url)
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    posting = true
                }
            }
        }
        .sheet(isPresented: $showCoverPhoto) {
            PhotoPicker { image in coverDraft = image }
        }
        .fullScreenCover(isPresented: $posting) { publishSheet }

        .confirmationDialog(Tr("这条动态"), isPresented: Binding(
            get: { actionMoment != nil },
            set: { if !$0 { actionMoment = nil } }
        ), titleVisibility: .visible) {
            if let m = actionMoment {
                if m.likedByMe == true {
                    Button(Tr("取消赞")) { like(m) }
                } else {
                    Button(Tr("赞")) { like(m) }
                }
                Button(Tr("评论")) {
                    commentsSheet = m
                }
                if mineOnly {
                    Button(m.pinned == true ? Tr("取消置顶") : Tr("置顶")) {
                        togglePin(m)
                    }
                    Button(Tr("删除"), role: .destructive) {
                        actionMoment = nil
                        pendingDeleteMoment = m
                    }
                }
            }
            Button(Tr("取消"), role: .cancel) { actionMoment = nil }
        }
        .overlay {
            if let moment = pendingDeleteMoment {
                PanelConfirmDialog(
                    title: Tr("删除这条朋友圈？"),
                    okText: Tr("删除"),
                    danger: true,
                    message: Tr("删除后无法恢复，点赞和评论也会一起移除。"),
                    symbol: "trash.fill",
                    onOk: {
                        pendingDeleteMoment = nil
                        remove(moment)
                    },
                    onCancel: { pendingDeleteMoment = nil }
                )
            }
        }
    }

    private func toggleCoverLock() {
        guard coverEditable else { return }
        withSystemAnimation(.easeOut(duration: 0.3)) {
            if coverLocked {
                coverLocked = false
                coverLockPull = 0
            } else {
                coverLockPull = min(420, max(240, coverPullBox.value))
                coverLocked = true
            }
        }
    }

    private func coverView(_ extra: CGFloat) -> some View {
        ZStack(alignment: .top) {
            C.pageBg

            if let coverPreview {
                Image(uiImage: coverPreview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: max(1, L.width),
                           height: L.coverH + extra)
                    .clipped()
            } else if cover.isEmpty {

                if UIImage(named: "moments-cover") != nil {

                    Image("moments-cover")
                        .resizable()
                        .scaledToFill()
                        .frame(width: L.width, height: L.coverH + extra)
                        .clipped()
                } else {
                    LinearGradient(colors: [Color(hex: 0x0D3B66), Color(hex: 0x1D6FB8), Color(hex: 0x0099FF)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            } else {
                RemoteImage(path: cover, icon: "photo", mode: .fill, maxSide: 2560)
                    .frame(width: max(1, L.width),
                           height: L.coverH + extra)
                    .clipped()
                    .id(cover)
            }

            if cover.isEmpty && coverEditable {
                VStack(spacing: 10) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(Color.black.opacity(0.48)))

                    Text(Tr("设置生活圈封面"))
                        .font(pf(16.5, .semibold))
                        .foregroundColor(.white)

                    Text(Tr("从相册选一张图，让朋友一眼记住你"))
                        .font(pf(12.2))
                        .foregroundColor(.white.opacity(0.82))
                        .multilineTextAlignment(.center)

                    Button {
                        coverMenu = true
                    } label: {
                        Text(Tr("立即设置"))
                            .font(pf(14.5, .semibold))
                            .foregroundColor(.white)
                            .frame(width: 118, height: 38)
                            .background(Capsule(style: .continuous)
                                .fill(C.green.opacity(0.92)))
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.42), lineWidth: 0.8)
                            }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: 286)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.58)))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.24), lineWidth: 0.7)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
                .zIndex(4)
            }

            Group {
                if scheme == .dark {
                    HarmonyDarkMask(strength: 0.94)
                        .mask(
                            LinearGradient(
                                colors: [Color.black, Color.black.opacity(0.70), Color.clear],
                                startPoint: .top, endPoint: .bottom)
                        )
                } else {
                    LinearGradient(colors: [Color.black.opacity(max(0, UIConfig.num("momentTopMask", 0.20))),
                                            Color.black.opacity(0)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
                .frame(height: max(L.safeTop + 56, UIConfig.num("momentTopMaskH", 150)))
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)

            Group {
                if scheme == .dark {
                    HarmonyDarkMask(strength: 0.96)
                        .mask(
                            LinearGradient(
                                colors: [Color.clear, Color.black.opacity(0.78), Color.black],
                                startPoint: .top, endPoint: .bottom)
                        )
                } else {
                    LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.22),
                                            Color.black.opacity(0.36)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
                .frame(height: L.coverH * 0.62)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .offset(y: -momentProfileFooterHeight)
                .allowsHitTesting(false)

            if coverEditable {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleCoverLock() }
                    .zIndex(2)
            }

            if coverEditable && !cover.isEmpty {
                HStack {
                    Button {
                        coverMenu = true
                    } label: {
                        Text(Tr("换封面"))
                            .font(pf(12.5, .medium))
                            .foregroundColor(.white)
                            .frame(width: 88, height: 32)
                            .background(Capsule()
                                .fill(Color.black.opacity(0.62)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.24), lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 12)
                .padding(.bottom, momentProfileFooterHeight + 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .zIndex(4)
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(owner?.name ?? "")
                        .font(pf(17, .semibold))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.55), radius: 4, x: 0, y: 1)
                        .lineLimit(1)
                }
                .padding(.bottom, 24)
                VStack(spacing: 4) {
                    Avatar(path: owner?.avatarPath ?? "", size: L.coverAvatar, radius: 8)
                        .shadow(color: Color.black.opacity(0.28), radius: 5, x: 0, y: 2)
                    if let sign = signature {
                        Text(sign)
                            .font(pf(12.5))
                            .foregroundColor(C.label)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.dyn(0xFFFFFF, 0x000000).opacity(0.62)))
                            .frame(width: L.coverAvatar + 56, alignment: .center)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 16)
            .padding(.bottom, 8)
            .allowsHitTesting(false)
        }
        .frame(height: L.coverH + extra + momentProfileFooterHeight)
        .zIndex(1)

        .contentShape(Rectangle())
    }

    private func dayLabel(_ s: String?) -> String {
        guard let d = TimeFmt.date(s) else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return Tr("今天") }
        if cal.isDateInYesterday(d) { return Tr("昨天") }
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: d),
                                      to: cal.startOfDay(for: Date())).day ?? 99
        if days == 2 { return Tr("前天") }
        return cal.isDate(d, equalTo: Date(), toGranularity: .year)
            ? Self.monthDayFormatter.string(from: d)
            : Self.yearMonthDayFormatter.string(from: d)
    }

    private func fullDateLabel(_ s: String?) -> String {
        guard let d = TimeFmt.date(s) else { return "" }
        return Self.yearMonthDayFormatter.string(from: d)
    }

    private struct FoldRow: Identifiable {
        var id: String { first.id }
        var first: Moment
        var rest: [Moment]
    }

    private var foldRows: [FoldRow] { foldRowsCache }

    private func rebuildFoldRows(_ source: [Moment]) {
        let timeline = source.filter { $0.pinned != true }
        let win = UIConfig.num("momentFoldWindow", 10) * 60_000
        guard win > 0 else {
            foldRowsCache = timeline.map { FoldRow(first: $0, rest: []) }
            return
        }
        var out: [FoldRow] = []
        var i = 0
        while i < timeline.count {
            let head = timeline[i]
            var rest: [Moment] = []
            let headAt = TimeFmt.date(head.createdAt) ?? Date.distantPast
            var j = i + 1
            while j < timeline.count {
                let nxt = timeline[j]

                guard let aid = head.authorId, !aid.isEmpty, nxt.authorId == aid else { break }
                let nextAt = TimeFmt.date(nxt.createdAt) ?? Date.distantPast

                if abs(headAt.timeIntervalSince(nextAt)) > win / 1000 { break }
                rest.append(nxt)
                j += 1
            }
            out.append(FoldRow(first: head, rest: rest))
            i = j
        }
        foldRowsCache = out
    }

    private func packedRow(_ row: FoldRow) -> some View {
        Button {

            groupPage = MomentGroup(id: row.first.id,
                                    title: row.first.author?.name ?? Tr("朋友圈"),
                                    moments: row.rest)
            showGroupPage = true
        } label: {
            HStack(spacing: 6) {
                Text(Tr("余下") + " \(row.rest.count) " + Tr("条"))
                    .font(pf(14))
                    .foregroundColor(Color(hex: 0x576B95))
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: 0x576B95))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var displayedMoments: [Moment] {
        MomentStressFixture.isActive
            ? stressLoadedMoments
            : moments
    }

    private var nativeMomentActions: NativeMomentActions {
        NativeMomentActions(
            openComments: { commentsSheet = $0 },
            openImage: { moment, index in
                let paths = moment.images ?? []
                guard paths.indices.contains(index) else { return }
                viewerPaths = paths
                viewerIndex = index
            },
            openVideo: { momentVideo = $0 },
            openAvatar: { cardUser = $0 },
            openLikes: { likes in
                likesSnapshot = likes
                showLikes = true
            },
            avatarPathFor: { app.contact(for: $0)?.avatarPath ?? "" },
            isFriend: { app.contact(for: $0) != nil },
            like: { like($0) },
            more: { actionMoment = $0 }
        )
    }

    private var momentStressStatus: String? {
        guard MomentStressFixture.isActive else { return nil }
        return "已加载 \(stressLoadedCount) / \(MomentStressFixture.count)"
    }

    private var momentFooterText: String? {
        var rows: [String] = []
        if hasMoreMoments {
            rows.append(Tr("正在加载…"))
        } else if momentTotal > 0 {
            rows.append(Tr("没有更多了"))
        }
        if !mineOnly,
           !(feedUserId ?? "").isEmpty,
           (feedUserId ?? "") != (app.me?.id ?? ""),
           feedRange == "3d" || feedRange == "6m" {
            rows.append(feedRange == "3d"
                        ? Tr("朋友仅展示最近三天的朋友圈")
                        : Tr("朋友仅展示最近半年的朋友圈"))
        }
        return rows.isEmpty ? nil : rows.joined(separator: "\n")
    }

    private var navBar: some View {
        ZStack {

            if solid {
                Text(Tr("生活圈"))
                    .font(pf(UIConfig.num("navTitle", 17)))
                    .foregroundColor(C.label)
            }

            HStack(spacing: 0) {

                Button { dismiss() } label: {
                    FlexIcon(custom: IconOverrides.custom("nav.back"),
                             size: 20, color: solid ? C.label : .white,
                             symbol: "chevron.left", weight: .medium)
                        .frame(width: 56, height: L.navH)
                        .shadow(color: solid ? .clear : Color.black.opacity(0.55), radius: 2, x: 0, y: 1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                ZStack(alignment: .topTrailing) {
                    Button { showNoticeList = true } label: {
                        FlexIcon(custom: IconOverrides.custom("nav.momentsBell"), size: 21,
                                 color: solid ? C.label : .white, symbol: "bell", weight: .medium)
                            .frame(width: 40, height: 44)
                            .shadow(color: solid ? .clear : Color.black.opacity(0.55), radius: 2, x: 0, y: 1)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if app.momentNoticeUnread > 0 {
                        Circle().fill(Color(.systemRed))
                            .frame(width: 8, height: 8)
                            .offset(x: -7, y: 9)
                    }
                }

                SVGIcon(markup: I.camera, size: 26, color: solid ? C.label : .white)
                    .frame(width: 44, height: 44)
                    .shadow(color: solid ? .clear : Color.black.opacity(0.55), radius: 2, x: 0, y: 1)
                    .contentShape(Rectangle())
                    .onTapGesture { openComposer() }
                    .onLongPressGesture(minimumDuration: 0.45, maximumDistance: 26) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showVideoShoot = true
                    }
                .padding(.trailing, 6)
                .contentShape(Rectangle())
            }
        }
        .frame(height: L.navH)

        .background(alignment: .top) {
            if solid {
                ScrollActiveGlassMask(base: C.pageBg, active: momentsScrollActive)
                    .frame(height: L.navH + momentsGlassHeaderExtension)
                    .padding(.bottom, -momentsGlassHeaderExtension)
                    .ignoresSafeArea(edges: .top)
            }
        }
        .animation(.easeOut(duration: 0.18), value: solid)
        .zIndex(25)
        .allowsHitTesting(true)
    }

    private var momentsGlassHeaderExtension: CGFloat { 56 }

    private func openPhoto(_ path: String, in moment: Moment) {
        guard Date() >= tapLockUntil else { return }
        let paths = moment.images ?? []
        guard let index = paths.firstIndex(of: path) else { return }
        viewerPaths = paths
        viewerIndex = index
    }

    private func openNotice(_ n: MomentNotice) {
        let mid = n.momentId ?? ""
        guard !mid.isEmpty else { return }
        if let hit = moments.first(where: { $0.id == mid }) { openMoment(hit); return }
        Task {
            await pollNewMoments()
            if let hit = moments.first(where: { $0.id == mid }) {
                openMoment(hit)
            } else {
                app.show(Tr("那条动态在更下面的记录里，往下翻就能看到"))
            }
        }
    }

    private func openMoment(_ m: Moment) {
        if let paths = m.images, !paths.isEmpty {
            viewerPaths = paths
            viewerIndex = 0
            return
        }
        if let v = m.video, !v.isEmpty {
            let full = v.hasPrefix("http") ? v : API.shared.base + v
            if let u = URL(string: full) { momentVideo = u; return }
        }
        app.show(m.content ?? "")
    }

    private var publishSheet: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    closeComposer()
                } label: {
                    Text(Tr("取消"))
                        .font(pfStyled(size: 16.5, weight: .regular))
                        .foregroundStyle(C.label)
                        .frame(height: L.navH)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SystemComposerPressStyle())

                Spacer(minLength: 12)

                Button { publish() } label: {
                    Text(uploading ? Tr("发表中…") : Tr("发表"))
                        .font(pfStyled(size: 16.5, weight: .semibold))
                        .foregroundColor(canPublish
                                         ? Color(hex: 0x07C160)
                                         : C.subLabel.opacity(0.62))
                        .frame(height: L.navH)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SystemComposerPressStyle())
                .disabled(!canPublish)
            }
            .padding(.horizontal, 16)
            .frame(height: L.navH)
            .background {
                ZStack {
                    NativeGlassHeaderMaterial(forcedDark: scheme == .dark)
                    composerSurface
                        .opacity(scheme == .dark ? 0.76 : 0.84)
                }
                .ignoresSafeArea(edges: .top)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(composerRule.opacity(0.72))
                    .frame(height: 0.5)
            }

            if !publishError.isEmpty {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(C.red)
                    Text(publishError)
                        .font(pf(13.5))
                        .foregroundColor(C.label)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.dyn(0xFFF5F5, 0x241719))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(C.hairline)
                        .frame(height: 0.5)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    if uploading {
                        VStack(spacing: 6) {
                            ProgressView(value: publishProgress)
                                .progressViewStyle(.linear)
                                .tint(Color(hex: 0x07C160))
                            HStack(spacing: 6) {
                                Text(publishStatus.isEmpty ? Tr("正在发表…") : publishStatus)
                                    .font(pf(12))
                                    .foregroundColor(C.subLabel)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text("\(Int(min(1, max(0, publishProgress)) * 100))%")
                                    .font(pf(12, .medium))
                                    .foregroundColor(C.subLabel)
                                    .monospacedDigit()
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(composerSurface)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(composerRule)
                                .frame(height: 0.5)
                        }
                    }

                    ZStack(alignment: .topLeading) {
                        if draft.isEmpty {
                            Text(Tr("这一刻的想法…"))
                                .font(pf(17))
                                .foregroundColor(C.subLabel)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $draft)
                            .font(pf(17))
                            .frame(minHeight: 104)
                            .scrollContentBackground(.hidden)
                    }
                    .padding(.horizontal, 12)
                    .background(composerSurface)

                    composerGrid
                        .padding(.horizontal, 16)
                        .padding(.top, 14)

                    VStack(spacing: 0) {
                        HairLine(inset: 16)
                        composerRow(icon: "location", title: Tr("所在位置"),
                                    value: draftLocation.isEmpty ? Tr("不显示位置") : draftLocation) {
                            showLocation = true
                        }
                        HairLine(inset: 16)
                        composerRow(icon: "eye", title: Tr("谁可以看"), value: visibilityName) {
                            showVisibility = true
                        }
                        HairLine(inset: 16)
                        composerRow(icon: "at", title: Tr("提醒谁看"),
                                    value: remindIds.isEmpty ? "" : "\(remindIds.count) 个人") {
                            pickMode = "at"
                            showPick = true
                        }
                    }
                    .background(composerSurface)
                    .padding(.top, 18)
                }
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
        }

        .background(composerSurface.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .interactiveDismissDisabled(uploading)
        .swipeBack { posting = false }
        .hidesTabBar()

            .sheet(isPresented: $showMomentAlbum, onDismiss: { showMomentAlbum = false }) {
                MomentPicker(limit: max(1, 9 - picked.count)) { r in
                    switch r {
                    case .images(let imgs):
                        let room = 9 - picked.count
                        if imgs.count > room { app.show("最多 9 张图，还能再加 \(room) 张") }
                        picked.append(contentsOf: imgs.prefix(max(0, room)))
                    case .video(let url):
                        Task { await prepareVideo(url) }
                    }
                }
            }
            .confirmationDialog(Tr("谁可以看"), isPresented: $showVisibility, titleVisibility: .visible) {
                Button(Tr("公开（所有好友可见）")) { visibility = "public" }
                Button(Tr("私密（仅自己可见）")) { visibility = "private" }
                Button(Tr("部分可见…")) { visibility = "partial"; pickMode = "partial"; showPick = true }
                Button(Tr("不给谁看…")) { visibility = "exclude"; pickMode = "exclude"; showPick = true }
                Button(Tr("取消"), role: .cancel) { }
            }
            .sheet(isPresented: $showPick) { friendPickSheet }
            .sheet(isPresented: $showLocation) {
                PlacePickerSheet(text: $draftLocation)
            }

            .sheet(isPresented: $showCamera) {
                CameraPicker(onPick: { image in
                    picked = [image]
                }, onVideo: { url in
                    Task { await prepareVideo(url) }
                })
            }

            .alert(Tr("不保留这次编辑？"), isPresented: $confirmDiscard) {
                Button(Tr("继续编辑"), role: .cancel) { }
                Button(Tr("不保留"), role: .destructive) { resetComposer() }
            }
    }

    private var canPublish: Bool {
        !uploading && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                       || !picked.isEmpty || pickedVideo != nil)
    }

    private var composerSurface: Color {
        Color.dyn(0xFFFFFF, 0x111111)
    }

    private var composerRule: Color {
        Color.dyn(0xE7E7E7, 0x2A2A2A)
    }

    private var composerGrid: some View {
        let gap: CGFloat = 6
        let side = (L.width - 32 - gap * 2) / 3
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: gap), count: 3),
                         alignment: .leading, spacing: gap) {

            if pickedVideo != nil {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        if let c = videoCover {
                            Image(uiImage: c)
                                .resizable()
                                .scaledToFill()
                        } else {
                            C.searchBg
                        }
                        Color.black.opacity(videoProgress > 0.01 ? 0.42 : 0.22)
                        VStack(spacing: 6) {
                            if videoProgress > 0.01 {

                                ZStack {
                                    Circle().stroke(Color.white.opacity(0.30), lineWidth: 4)
                                        .frame(width: 50, height: 50)
                                    Circle()
                                        .trim(from: 0, to: max(0.04, min(1, videoProgress)))
                                        .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                        .frame(width: 50, height: 50)
                                    Text("\(Int(min(1, videoProgress) * 100))%")
                                        .font(pfStyled(size: 12.5, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            } else {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white.opacity(0.95))
                            }
                            if videoSeconds > 0, videoProgress <= 0.01 {
                                Text(String(format: "%02d:%02d", videoSeconds / 60, videoSeconds % 60))
                                    .font(pfStyled(size: 11, weight: .medium))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .frame(width: side, height: side)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    if !uploading {
                        Button {
                            pickedVideo = nil
                            videoCover = nil
                            videoSeconds = 0
                            videoWH = nil
                            videoProgress = 0
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.black.opacity(0.6)))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                    }
                }
            }
            ForEach(picked.indices, id: \.self) { i in
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: picked[i])
                        .resizable()
                        .scaledToFill()
                        .frame(width: side, height: side)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .contentShape(Rectangle())
                        .onDrag {
                            dragIndex = i
                            return NSItemProvider(object: String(i) as NSString)
                        }
                        .onDrop(of: [UTType.text],
                                delegate: MomentGridDrop(index: i, items: $picked, dragIndex: $dragIndex))
                    Button {
                        picked.remove(at: i)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                }
            }
            if picked.count < 9 && pickedVideo == nil {

                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(C.searchBg)
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .light))
                        .foregroundColor(C.subLabel)
                }
                .frame(width: side, height: side)
                .contentShape(Rectangle())
                .onTapGesture { showMomentAlbum = true }
                .onLongPressGesture(minimumDuration: 0.45, maximumDistance: 26) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showCamera = true
                }
            }
        }
    }

    private func composerRow(icon: String, title: String, value: String,
                             tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(C.label)
                    .frame(width: 20)
                Text(title).font(pf(16)).foregroundColor(C.label)
                Spacer(minLength: 8)
                if !value.isEmpty {
                    Text(value).font(pf(15)).foregroundColor(C.subLabel).lineLimit(1)
                }
                Chevron(size: 9, line: 1.6)
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var visibilityName: String {
        switch visibility {
        case "private": return "仅自己"
        case "partial": return "部分可见"
        case "exclude": return "不给谁看"
        default: return "公开"
        }
    }

    private var friendPickSheet: some View {
        NavigationStack {
            List {
                ForEach(app.contacts) { u in
                    Button {
                        if pickMode == "at" {
                            if remindIds.contains(u.id) { remindIds.remove(u.id) } else { remindIds.insert(u.id) }
                        } else if pickMode == "partial" {
                            if visibleTo.contains(u.id) { visibleTo.remove(u.id) } else { visibleTo.insert(u.id) }
                        } else {
                            if hiddenFrom.contains(u.id) { hiddenFrom.remove(u.id) } else { hiddenFrom.insert(u.id) }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Avatar(path: u.avatarPath, size: 38, radius: 6)
                            Text(u.name).font(pf(16)).foregroundColor(C.label)
                            Spacer()
                            let on = pickMode == "at" ? remindIds.contains(u.id)
                                : (pickMode == "partial" ? visibleTo.contains(u.id) : hiddenFrom.contains(u.id))
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(on ? C.green : C.subLabel)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(pickMode == "at" ? "提醒谁看"
                             : (pickMode == "partial" ? "选择可见的好友" : "选择不看的好友"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(Tr("好了")) { showPick = false } } }
        }
    }

    private func startPullRefresh() {
        pulling = true
        spinTask?.cancel()
        spinTask = Task { @MainActor in
            var angle = spin
            let started = Date()
            while !Task.isCancelled {
                angle += 14
                spin = angle
                try? await Task.sleep(nanoseconds: 16_000_000)
                if Date().timeIntervalSince(started) > 1.0 { break }
            }

            let finished = await withPullTimeout(seconds: 6) {
                if self.coverEditable { self.app.me = try? await API.shared.me() }
                await self.reload()
            }
            if !finished {
                CrashCatcher.note("朋友圈", "下拉刷新的网络请求超 6 秒，先把彩球收掉")
            }
            pullY = 0
            spin = 0
            pulling = false
        }
    }

    private func withPullTimeout(seconds: Double,
                                 _ work: @escaping @MainActor () async -> Void) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { await work(); return true }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    private func reload() async {
        momentPrefetchTask?.cancel()
        prefetchedMoments.removeAll(keepingCapacity: true)
        prefetchedHasMore = false
        if MomentStressFixture.isActive {
            stressLoadedCount = min(
                MomentStressFixture.count,
                max(Self.stressMomentWindow, stressLoadedCount)
            )
            if stressLoadedMoments.count > stressLoadedCount {
                setStressLoadedMoments(
                    Array(stressLoadedMoments.prefix(stressLoadedCount))
                )
            } else if stressLoadedMoments.count < stressLoadedCount {
                setStressLoadedMoments(
                    stressLoadedMoments + MomentStressFixture.moments(
                        range: stressLoadedMoments.count..<stressLoadedCount
                    )
                )
            }
            momentTotal = MomentStressFixture.count
            hasMoreMoments = stressLoadedCount < MomentStressFixture.count
            return
        }

        if let feed = try? await API.shared.momentsFeed(
            limit: Self.momentPageSize,
            userId: feedUserId
        ) {
            let mergedPage = applyNewestMomentPage(feed.moments)
            momentTotal = feed.total
            feedRange = feed.range
            app.momentNoticeUnread = feed.noticeUnread
            hasMoreMoments = mergedPage.count < feed.total || feed.hasMore

            if target == nil && !mineOnly {
                LocalStore.saveMoments(mergedPage, userId: app.me?.id ?? "")
            }
        } else {

            let cached = LocalStore.cachedMoments(userId: app.me?.id ?? "")
            let fallback = cached.isEmpty ? app.moments : cached
            setMomentsWithoutAnimation(Array(fallback.prefix(Self.momentPageSize)))
            hasMoreMoments = fallback.count > Self.momentPageSize
        }

        if target == nil {
            await API.shared.markMomentsSeen()
            app.momentsUnread = 0
        }
        scheduleMomentPrefetch()
    }

    private func loadMoreMoments() async {
        if MomentStressFixture.isActive {
            guard hasMoreMoments, !loadingMore else { return }
            loadingMore = true
            let previous = stressLoadedCount
            let next = min(
                MomentStressFixture.count,
                previous + Self.stressMomentPageSize
            )
            momentTotal = MomentStressFixture.count
            stressLoadedCount = next
            if stressLoadedCount > previous {
                setStressLoadedMoments(
                    stressLoadedMoments + MomentStressFixture.moments(
                        range: previous..<stressLoadedCount
                    )
                )
            }
            hasMoreMoments = stressLoadedCount < MomentStressFixture.count
            loadingMore = false
            return
        }
        if let momentPrefetchTask {
            await momentPrefetchTask.value
        }
        if !prefetchedMoments.isEmpty {
            loadingMore = true
            let known = Set(moments.map(\.id))
            let page = prefetchedMoments.filter { !known.contains($0.id) }
            let more = prefetchedHasMore
            prefetchedMoments.removeAll(keepingCapacity: true)
            prefetchedHasMore = false
            loadingMore = false
            appendMomentPage(page, hasMore: more)
            return
        }
        guard hasMoreMoments, !loadingMore, let last = moments.last else { return }
        loadingMore = true
        if let feed = try? await API.shared.momentsFeed(limit: Self.momentPageSize, before: last.createdAt, beforeId: last.id,
                                                        userId: feedUserId) {
            let known = Set(moments.map { $0.id })
            appendMomentPage(
                feed.moments.filter {
                    !known.contains($0.id) && !locallyDeletedMomentIds.contains($0.id)
                },
                hasMore: feed.hasMore && !feed.moments.isEmpty
            )
        } else {
            hasMoreMoments = false
        }
        loadingMore = false
        scheduleMomentPrefetch()
    }

    private func appendMomentPage(_ page: [Moment], hasMore: Bool) {
        guard !page.isEmpty else {
            hasMoreMoments = hasMore
            return
        }
        let known = Set(moments.map(\.id))
        setMomentsWithoutAnimation(moments + page.filter { !known.contains($0.id) })
        hasMoreMoments = hasMore
        scheduleMomentPrefetch()
    }

    private func pollNewMoments() async {
        guard !MomentStressFixture.isActive else { return }
        guard let feed = try? await API.shared.momentsFeed(
            limit: Self.momentPageSize,
            userId: feedUserId
        ) else { return }
        let mergedPage = applyNewestMomentPage(feed.moments)
        momentTotal = feed.total
        hasMoreMoments = mergedPage.count < feed.total || feed.hasMore
        if target == nil && !mineOnly {
            app.moments = mergedPage
            LocalStore.saveMoments(mergedPage, userId: app.me?.id ?? "")
        }
        scheduleMomentPrefetch()
    }

    private func scheduleMomentPrefetch() {
        guard !MomentStressFixture.isActive,
              hasMoreMoments,
              prefetchedMoments.isEmpty,
              !prefetchingMoments,
              let last = moments.last else { return }
        momentPrefetchTask?.cancel()
        momentPrefetchTask = Task { @MainActor in
            await prefetchNextMomentsPage()
        }
    }

    private func prefetchNextMomentsPage() async {
        guard !MomentStressFixture.isActive,
              hasMoreMoments,
              !prefetchingMoments,
              prefetchedMoments.isEmpty,
              let last = moments.last else { return }
        prefetchingMoments = true
        defer { prefetchingMoments = false }
        guard let feed = try? await API.shared.momentsFeed(
            limit: Self.momentPageSize,
            before: last.createdAt,
            beforeId: last.id,
            userId: feedUserId
        ) else { return }
        guard moments.last?.id == last.id else { return }
        let known = Set(moments.map(\.id))
        prefetchedMoments = feed.moments.filter {
            !known.contains($0.id) && !locallyDeletedMomentIds.contains($0.id)
        }
        prefetchedHasMore = feed.hasMore && !prefetchedMoments.isEmpty
    }

    @discardableResult
    private func applyNewestMomentPage(_ page: [Moment]) -> [Moment] {
        var cleanPage = page.filter { !locallyDeletedMomentIds.contains($0.id) }
        let pageIds = Set(cleanPage.map(\.id))
        locallyPostedMoments = locallyPostedMoments.filter { !pageIds.contains($0.key) }
        let pendingLocal = locallyPostedMoments.values.sorted {
            ($0.createdAt ?? "") > ($1.createdAt ?? "")
        }
        if !pendingLocal.isEmpty {
            cleanPage = pendingLocal + cleanPage.filter {
                !locallyPostedMoments.keys.contains($0.id)
            }
        }
        var merged = cleanPage
        if moments.count > Self.momentPageSize {
            let pageIds = Set(cleanPage.map(\.id))
            let older = moments.dropFirst(Self.momentPageSize).filter {
                !pageIds.contains($0.id) && !locallyDeletedMomentIds.contains($0.id)
            }
            merged.append(contentsOf: older)
        }
        if merged != moments {
            setMomentsWithoutAnimation(merged)
        }
        return merged
    }

    private func insertLocallyPostedMoment(_ moment: Moment) {
        locallyDeletedMomentIds.remove(moment.id)
        locallyPostedMoments[moment.id] = moment
        var next = moments.filter { $0.id != moment.id }
        next.insert(moment, at: 0)
        if next.count > Self.momentPageSize {
            next = Array(next.prefix(Self.momentPageSize))
        }
        setMomentsWithoutAnimation(next)
        momentTotal = max(momentTotal + 1, next.count)
        hasMoreMoments = hasMoreMoments || momentTotal > next.count
        if target == nil && !mineOnly {
            LocalStore.saveMoments(next, userId: app.me?.id ?? "")
        }
        var global = app.moments
        if let index = global.firstIndex(where: { $0.id == moment.id }) {
            global[index] = moment
        } else {
            global.insert(moment, at: 0)
        }
        app.moments = global
    }

    private func setMomentsWithoutAnimation(_ next: [Moment]) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            moments = next
            momentFeedRevision &+= 1
        }
    }

    private func setStressLoadedMoments(_ next: [Moment]) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            stressLoadedMoments = next
            momentFeedRevision &+= 1
        }
    }

    private func publish() {
        uploading = true
        publishError = ""
        publishProgress = 0.02
        publishStatus = pickedVideo == nil
            ? Tr("正在准备图片…")
            : Tr("正在准备视频…")
        Task {

            if let v = pickedVideo {
                do {
                    DispatchQueue.main.async { videoProgress = 0.02 }
                    var file = v
                    var from = 0.0
                    if await MediaTool.needsCompress(v) {
                        if let small = await MediaTool.compress(v, onProgress: { p in
                            DispatchQueue.main.async {
                                videoProgress = min(0.45, p * 0.45)
                                publishProgress = videoProgress
                                publishStatus = Tr("正在压缩视频…")
                            }
                        }) { file = small; from = 0.45 }
                    }
                    guard let up = await MediaTool.upload(file, onProgress: { p in
                        DispatchQueue.main.async {
                            videoProgress = from + p * (1 - from)
                            publishProgress = videoProgress * 0.92
                            publishStatus = Tr("正在上传视频…")
                        }
                    }, skipServerTranscode: true) else {
                        throw APIError.message("视频上传失败")
                    }

                    var cp = ""
                    let coverImg: UIImage?
                    if let c = videoCover { coverImg = c } else { coverImg = await MediaTool.firstFrame(file) }
                    if let c = coverImg { cp = (try? await API.shared.uploadCover(image: c)) ?? "" }
                    await MainActor.run {
                        publishProgress = 0.96
                        publishStatus = Tr("正在发布…")
                    }
                    let wh = videoWH
                    let created = try await API.shared.postMoment(
                        content: draft, images: [],
                        video: up, videoCover: cp,
                        videoSeconds: videoSeconds,
                        videoW: wh?.w ?? 0, videoH: wh?.h ?? 0,
                        visibility: visibility,
                        visibleTo: Array(visibleTo),
                        hiddenFrom: Array(hiddenFrom),
                        location: draftLocation
                    )
                    if let created {
                        await MainActor.run { insertLocallyPostedMoment(created) }
                    }
                    await remindFriends()
                    app.show(Tr("已发表"))
                } catch {
                    let message = (error as? APIError)?.errorDescription ?? "视频发表失败"
                    await MainActor.run {
                        publishError = message
                        uploading = false
                    }
                    app.show(message)
                    return
                }
                resetComposer()
                await reload()
                await app.loadMoments()
                return
            }
            var urls: [String] = []
            var sizes: [String: [Int]] = [:]

            var mResults: [(idx: Int, url: String, w: Int, h: Int, data: Data)] = []
            let total = max(1, picked.count)
            var completed = 0
            var uploadError: String?
            await withTaskGroup(of: (Int, String, Int, Int, Data, String?).self) { group in
                var nextIdx = 0
                func addUpload(_ i: Int) {
                    let img = picked[i]
                    let w = Int(img.size.width.rounded()), h = Int(img.size.height.rounded())
                    group.addTask {
                        do {
                            let up = try await API.shared.uploadImageForSend(
                                img, original: false, maxSide: 1080, quality: 0.70
                            )
                            return (i, up.url, w, h, up.data, nil)
                        } catch {
                            return (
                                i,
                                "",
                                w,
                                h,
                                Data(),
                                (error as? APIError)?.errorDescription
                                    ?? "图片上传失败"
                            )
                        }
                    }
                }
                while nextIdx < min(6, picked.count) { addUpload(nextIdx); nextIdx += 1 }
                for await r in group {
                    if let failure = r.5 {
                        if uploadError == nil { uploadError = failure }
                    } else if !r.1.isEmpty {
                        mResults.append((idx: r.0, url: r.1, w: r.2, h: r.3, data: r.4))
                    } else {
                        if uploadError == nil { uploadError = "图片上传不完整，请重试" }
                    }
                    completed += 1
                    let progress = 0.05 + Double(completed) / Double(total) * 0.72
                    await MainActor.run {
                        publishProgress = min(0.78, progress)
                        publishStatus = Tr("正在上传图片") + " \(min(completed, picked.count))/\(picked.count)"
                    }
                    if nextIdx < picked.count { addUpload(nextIdx); nextIdx += 1 }
                }
            }
            if let uploadError {
                await MainActor.run {
                    publishError = uploadError
                    uploading = false
                }
                app.show(uploadError)
                return
            }
            for r in mResults.sorted(by: { $0.idx < $1.idx }) {
                urls.append(r.url)

                sizes[r.url] = [r.w, r.h]
                let img = picked[r.idx]
                ImageStore.shared.put(r.url, img)
                ImageSizeCache.put(r.url, ImageBubble.thumb(img.size))
                if !r.data.isEmpty {
                    let bytes = r.data
                    Task.detached(priority: .utility) {
                        ImageStore.shared.diskWrite(r.url, bytes)
                        LocalStore.keep(r.url, data: bytes)
                    }
                }
            }
            do {
                await MainActor.run {
                    publishProgress = 0.84
                    publishStatus = Tr("正在发布…")
                }
                let created = try await API.shared.postMoment(
                    content: draft, images: urls,
                    imageSizes: sizes,
                    visibility: visibility,
                    visibleTo: Array(visibleTo),
                    hiddenFrom: Array(hiddenFrom),
                    location: draftLocation
                )
                if let created {
                    await MainActor.run { insertLocallyPostedMoment(created) }
                }
                await remindFriends()
                await MainActor.run {
                    publishProgress = 1
                    publishStatus = Tr("已发表")
                }
                app.show(Tr("已发表"))
            } catch {
                let message = (error as? APIError)?.errorDescription ?? "发表失败"
                await MainActor.run {
                    publishError = message
                    uploading = false
                }
                app.show(message)
                return
            }
            resetComposer()
            await reload()
            await app.loadMoments()
        }
    }

    private func remindFriends() async {
        guard !remindIds.isEmpty else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let tip = "我在朋友圈提到了你" + (text.isEmpty ? "" : "：" + String(text.prefix(30)))
        for fid in remindIds {
            if let chat = try? await API.shared.openDirect(userId: fid) {
                _ = try? await API.shared.send(chatId: chat.id, text: tip)
            }
        }
        await app.loadChats()
    }

    private func resetComposer() {
        draft = ""
        picked = []
        pickedVideo = nil
        videoCover = nil
        videoSeconds = 0
        videoWH = nil
        videoProgress = 0
        publishProgress = 0
        publishStatus = ""
        visibility = "public"
        visibleTo = []
        hiddenFrom = []
        draftLocation = ""
        remindIds = []
        uploading = false
        publishError = ""
        posting = false
        tapLockUntil = Date().addingTimeInterval(0.6)
    }

    private func openComposer() {
        resetComposer()
        posting = true
    }

    private func closeComposer() {
        let hasStuff = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !picked.isEmpty || pickedVideo != nil
        if hasStuff { confirmDiscard = true } else { resetComposer() }
    }

    private func prepareVideo(_ url: URL) async {
        let cover = await MediaTool.firstFrame(url)
        let secs = await MediaTool.seconds(url)
        let wh = await MediaTool.aspect(url)
        await MainActor.run {
            pickedVideo = url
            videoCover = cover
            videoSeconds = secs
            videoWH = wh
            videoProgress = 0
            picked = []
        }
    }

    private func changeCover(_ image: UIImage) {
        // Publish the in-memory pixels before any disk or network work so the
        // cover changes in the same touch frame.
        coverPreview = image
        let localPath = stageLocalImagePreview(image, prefix: "local-cover")
        setCoverOverride(localPath)
        if var me = app.me {
            me.momentCover = localPath
            app.me = me
        }
        Task {
            uploading = true
            guard let url = try? await API.shared.uploadCover(image: image) else {
                uploading = false
                app.show(Tr("已在本机生效，联网后自动同步"))
                return
            }

            setCoverOverride(url)
            if var me = app.me {
                me.momentCover = url
                app.me = me
            }
            do {
                if let updated = try await API.shared.updateMeChecked(["momentCover": url]) {
                    app.applyMyProfileUser(updated)
                    clearCoverOverride()
                } else {
                    app.applyMyProfileFields(["momentCover": url])
                }
                app.show(Tr("生活圈封面已更新"))
            } catch {
                setCoverOverride(localPath)
                if var me = app.me {
                    me.momentCover = localPath
                    app.me = me
                }
                app.show(Tr("已在本机生效，联网后自动同步"))
            }
            uploading = false
        }
    }

    private func setCoverOverride(_ path: String) {
        coverOverride = path
        UserDefaults.standard.set(path, forKey: coverOverrideKey)
    }

    private func clearCoverOverride() {
        coverOverride = ""
        UserDefaults.standard.removeObject(forKey: coverOverrideKey)
    }

    private func like(_ moment: Moment) {
        Task {
            if let err = await API.shared.likeMoment(id: moment.id) {
                app.show(err)
            } else {
                await reload()
            }
        }
    }

    private func togglePin(_ moment: Moment) {
        let next = !(moment.pinned == true)
        Task {
            await API.shared.pinMoment(id: moment.id, pinned: next)
            await reload()
            app.show(next ? Tr("已置顶，会固定显示在最上面") : Tr("已取消置顶"))
        }
    }

    private func deleteComment(_ momentId: String, _ commentId: String) {
        Task {
            if let err = await API.shared.deleteMomentComment(momentId: momentId, commentId: commentId) {
                app.show(err)
            } else {
                app.show(Tr("评论已删除"))
            }
            await reload()
        }
    }

    private func remove(_ moment: Moment) {
        let id = moment.id
        guard !id.isEmpty else { return }
        forgetMomentLocally(id)
        app.show(Tr("正在删除动态…"))
        Task {
            if let err = await API.shared.deleteMoment(id: id) {
                locallyDeletedMomentIds.remove(id)
                await reload()
                app.show(err)
            } else {
                await app.loadMoments()
                app.show(Tr("动态已删除"))
            }
        }
    }

    private func forgetMomentLocally(_ id: String) {
        guard !id.isEmpty else { return }
        locallyDeletedMomentIds.insert(id)
        momentPrefetchTask?.cancel()
        prefetchedMoments.removeAll { $0.id == id }
        let next = moments.filter { $0.id != id }
        setMomentsWithoutAnimation(next)
        momentTotal = max(0, momentTotal - 1)
        app.moments.removeAll { $0.id == id }
        if target == nil && !mineOnly {
            LocalStore.saveMoments(next, userId: app.me?.id ?? "")
        }
    }
}

struct MomentGroup: Identifiable {
    var id: String
    var title: String
    var moments: [Moment]
}

struct MomentGroupPage: View {
    let title: String
    let moments: [Moment]
    var onDeleted: (() -> Void)? = nil
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var viewerPaths: [String] = []
    @State private var viewerIndex: Int?
    @State private var commentsMoment: Moment?
    @State private var likesSnapshot: [MomentLike] = []
    @State private var showLikes = false
    @State private var videoURL: URL?
    @State private var cardUser: User?
    @State private var actionMoment: Moment?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                NavBar(title: title, back: { dismiss() })
                NativeMomentFeed(
                    moments: moments,
                    revision: moments.count,
                    dark: scheme == .dark,
                    mineOnly: false,
                    dayKey: "\(Lang.code)-\(scheme)-group-\(title)",
                    headerHeight: 0,
                    collapseOffset: 0,
                    onScrollActive: { _ in },
                    onCollapseChange: { _ in },
                    onPullChange: { _ in },
                    onPullEnd: { _ in },
                    onApproachingEnd: {},
                    actions: nativeMomentActions,
                    stressText: nil,
                    footerText: nil,
                    footerWaiting: false,
                    dayLabel: { fullDateLabel($0.createdAt) },
                    header: { _ in EmptyView() }
                )
                .background(C.pageBg)
            }

            if let i = viewerIndex, !viewerPaths.isEmpty {
                PhotoPager(paths: viewerPaths, startIndex: i, showActions: true) {
                    viewerIndex = nil
                }
                .zIndex(40)
            }
        }
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .sheet(item: $commentsMoment) { moment in
            MomentCommentsSheet(moment: moment) {
                onDeleted?()
            }
            .environmentObject(app)
        }
        .sheet(isPresented: $showLikes) {
            MomentLikesSheet(likes: likesSnapshot)
                .environmentObject(app)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
        }
        .fullScreenCover(isPresented: Binding(
            get: { videoURL != nil },
            set: { if !$0 { videoURL = nil } }
        )) {
            if let videoURL {
                VideoPlayerSheet(url: videoURL)
                    .environmentObject(app)
            }
        }
        .confirmationDialog(
            Tr("朋友圈操作"),
            isPresented: Binding(
                get: { actionMoment != nil },
                set: { if !$0 { actionMoment = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(Tr("删除"), role: .destructive) {
                guard let moment = actionMoment else { return }
                actionMoment = nil
                Task {
                    if let error = await API.shared.deleteMoment(id: moment.id) {
                        app.show(error)
                    } else {
                        onDeleted?()
                    }
                }
            }
            Button(Tr("取消"), role: .cancel) { actionMoment = nil }
        }
        .modifier(TapAvatarCard(cardUser: $cardUser))
    }

    private var nativeMomentActions: NativeMomentActions {
        NativeMomentActions(
            openComments: { commentsMoment = $0 },
            openImage: { moment, index in
                viewerPaths = moment.images ?? []
                viewerIndex = min(max(0, index), max(0, viewerPaths.count - 1))
            },
            openVideo: { videoURL = $0 },
            openAvatar: { cardUser = $0 },
            openLikes: {
                likesSnapshot = $0
                showLikes = true
            },
            avatarPathFor: { id in
                app.contact(for: id)?.avatarPath ?? ""
            },
            isFriend: { id in
                app.contact(for: id) != nil
            },
            like: { moment in
                Task {
                    if let error = await API.shared.likeMoment(id: moment.id) {
                        app.show(error)
                    }
                    await app.loadMoments()
                }
            },
            more: { actionMoment = $0 }
        )
    }

    private func fullDateLabel(_ s: String?) -> String {
        guard let d = TimeFmt.date(s) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: d)
    }

}

struct CoverAdjustSheet: View {
    let image: UIImage
    let frameSize: CGSize
    var onDone: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("拖动调整"), back: { dismiss() }) {
                Button {
                    render()
                } label: {
                    Text(Tr("完成"))
                        .font(pf(17, .semibold))
                        .foregroundColor(C.green)
                        .frame(height: L.navH)
                        .padding(.trailing, 16)
                }
                .buttonStyle(.plain)
            }

            ZStack {
                Color.black
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: frameSize.width, height: frameSize.height)
                    .scaleEffect(scale)
                    .offset(offset)
            }
            .frame(width: frameSize.width, height: frameSize.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { v in
                        offset = CGSize(width: baseOffset.width + v.translation.width,
                                        height: baseOffset.height + v.translation.height)
                    }
                    .onEnded { _ in baseOffset = offset }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { m in scale = max(1, min(3, baseScale * m)) }
                    .onEnded { _ in baseScale = scale }
            )

            Text(Tr("拖动挪位置，双指缩放，点「完成」保存"))
                .font(pf(12.5))
                .foregroundColor(C.subLabel)
                .padding(.top, 14)
            Spacer()
        }
        .background(C.pageBg.ignoresSafeArea(edges: .bottom))
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
    }

    @MainActor
    private func render() {

        let targetW: CGFloat = 2048
        let targetH = (targetW * frameSize.height / max(1, frameSize.width)).rounded()
        let k = targetW / max(1, frameSize.width)
        let view = Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: targetW, height: targetH)
            .scaleEffect(scale)
            .offset(x: offset.width * k, y: offset.height * k)
            .frame(width: targetW, height: targetH)
            .clipped()
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        if let out = renderer.uiImage { onDone(out) }
        dismiss()
    }
}

struct MomentGridDrop: DropDelegate {
    let index: Int
    @Binding var items: [UIImage]
    @Binding var dragIndex: Int?

    func dropEntered(info: DropInfo) {
        guard let from = dragIndex, from != index,
              items.indices.contains(from), items.indices.contains(index) else { return }
        withSystemAnimation(.easeInOut(duration: 0.16)) {
            items.move(fromOffsets: IndexSet(integer: from), toOffset: index > from ? index + 1 : index)
        }
        dragIndex = index
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragIndex = nil
        return true
    }
}

final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    static let shared = OneShotLocation()
    private let mgr = CLLocationManager()
    private var cont: CheckedContinuation<CLLocation?, Never>?
    private var timeout: Task<Void, Never>?

    func current() async -> CLLocation? {

        if let l = mgr.location, abs(l.timestamp.timeIntervalSinceNow) < 60 { return l }
        if cont != nil { return mgr.location }
        return await withCheckedContinuation { c in
            cont = c
            mgr.delegate = self
            mgr.desiredAccuracy = kCLLocationAccuracyHundredMeters
            let st = mgr.authorizationStatus
            if st == .notDetermined {

                mgr.requestWhenInUseAuthorization()
            } else if st == .denied || st == .restricted {
                finish(mgr.location)
            } else {
                mgr.requestLocation()
            }

            timeout?.cancel()
            timeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if Task.isCancelled { return }
                self?.finish(self?.mgr.location)
            }
        }
    }

    private func finish(_ loc: CLLocation?) {
        timeout?.cancel()
        timeout = nil
        cont?.resume(returning: loc)
        cont = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let st = manager.authorizationStatus
        if st == .notDetermined { return }
        if st == .denied || st == .restricted {
            finish(manager.location)
            return
        }
        if cont != nil { manager.requestLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(manager.location)
    }
}

struct PlacePickerSheet: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss

    @State private var places: [String] = []
    @State private var locating = true

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("所在位置"), back: { dismiss() })
            if locating {
                HStack { Spacer(); ProgressView(Tr("正在定位…")); Spacer() }
                    .frame(height: 90)
                    .background(C.cardBg)
            }
            ScrollView {
                VStack(spacing: 0) {
                    Button {
                        text = ""
                        dismiss()
                    } label: {
                        HStack {
                            Text(Tr("不显示位置")).font(pf(16)).foregroundColor(C.label)
                            Spacer()
                            if text.isEmpty { Image(systemName: "checkmark").foregroundColor(C.green) }
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    ForEach(places, id: \.self) { p in
                        HairLine(inset: 16)
                        Button {
                            text = p
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 15)).foregroundColor(C.subLabel)
                                Text(p).font(pf(16)).foregroundColor(C.label)
                                Spacer()
                                if text == p { Image(systemName: "checkmark").foregroundColor(C.green) }
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(C.cardBg)
                .padding(.top, 12)
            }
            Spacer()
        }
        .background(C.pageBg.ignoresSafeArea(edges: .bottom))
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task {
            let loc = await OneShotLocation.shared.current()
            guard let loc = loc else { locating = false; return }
            if let marks = try? await CLGeocoder().reverseGeocodeLocation(loc), let m = marks.first {
                var list: [String] = []
                if let name = m.name, !name.isEmpty { list.append(name) }
                if let city = m.locality, !city.isEmpty, !list.contains(city) { list.append(city) }
                if let sub = m.subLocality, !sub.isEmpty, !list.contains(sub) { list.append(sub) }
                if let prov = m.administrativeArea, !prov.isEmpty, !list.contains(prov) { list.append(prov) }
                places = list
            }
            locating = false
        }
    }
}

struct PickedGrid: View {
    let images: [UIImage]
    var onTap: (Int) -> Void

    private let gap: CGFloat = 6
    private let radius: CGFloat = 4

    var body: some View {
        if images.count == 1 {
            let img = images[0]
            let a = min(max(img.size.width / max(1, img.size.height), 0.75), 2.0)
            let limit = a >= 1 ? (L.width - 32) : (L.width - 32) * 0.62
            let w = min(limit, img.size.width)
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: w, height: min(w / a, 300))
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture { onTap(0) }
        } else {
            let cols = (images.count == 2 || images.count == 4) ? 2 : 3
            let maxW = L.width - 32
            let cell = (maxW - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let rows = stride(from: 0, to: images.count, by: cols).map { start in
                Array(start..<min(start + cols, images.count))
            }
            VStack(alignment: .leading, spacing: gap) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: gap) {
                        ForEach(rows[r], id: \.self) { i in
                            Image(uiImage: images[i])
                                .resizable()
                                .scaledToFill()
                                .frame(width: cell, height: cell)
                                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                                .contentShape(Rectangle())
                                .onTapGesture { onTap(i) }
                        }
                        if rows[r].count < cols { Spacer(minLength: 0) }
                    }
                }
            }
        }
    }
}
