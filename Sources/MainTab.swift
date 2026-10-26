import SwiftUI
import UIKit

struct MainTabView: View {
    @EnvironmentObject var app: AppState
    @State private var tab = 0
    @State private var shownCrash = false
    @AppStorage(XingjiNativePages.enabledKey) private var xingjiNativePages = true

    @ObservedObject private var lang = LangStore.shared

    @ObservedObject private var musicSheet = MusicSheet.shared

    @ObservedObject private var mallSheet = MallSheet.shared

    @ObservedObject private var realNameGate = RealNameGate.shared

    private var unreadTotal: Int {

        app.chats.reduce(0) { $0 + (($1.muted == true) ? 0 : ($1.unread ?? 0)) }
    }

    private var mutedOnlyUnread: Bool {
        unreadTotal == 0 && app.chats.contains { $0.muted == true && ($0.unread ?? 0) > 0 }
    }

    var body: some View {

        ZStack(alignment: .bottom) {

            ZStack {
                if xingjiNativePages {
                    XingjiNativePageHost(tab: $tab)
                } else if tab == 0 {
                    ChatsView()
                } else if tab == 1 {
                    ContactsView()
                } else if tab == 2 {
                    DiscoverView()
                } else {
                    MeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            .ignoresSafeArea(edges: app.tabBarHidden ? [] : .bottom)

            .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: app.tabBarHidden
                           ? 0
                           : L.tabH + L.safeBottom)
            }

            .overlay {
                if app.syncing || !app.syncText.isEmpty {
                    ZStack {
                        Color.black.opacity(0.16).ignoresSafeArea()
                        VStack(spacing: 14) {
                            if app.syncing { ProgressView().scaleEffect(1.15) }
                            Text(app.syncing ? "正在同步最近的聊天记录…"
                                             : (app.syncText.isEmpty ? "已同步最近的聊天记录" : app.syncText))
                                .font(pf(14))
                                .foregroundColor(C.label)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 26)
                        .padding(.vertical, 22)

                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(C.cardBg))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(C.hairline, lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.18), radius: 16, y: 4)
                    }
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
            }

            if !app.tabBarHidden {
                TabBar(selection: $tab,
                       badge: app.showDot("chats", auto: unreadTotal > 0) ? unreadTotal : 0,
                       contactsDot: app.showDot("contacts", auto: app.friendRequests > 0),
                       momentsDot: app.showDot("discover", auto: app.momentsUnread > 0),
                       meDot: app.showDot("me", auto: false))

                    .background {

                        if UIConfig.num("tabBarOpaqueBg", 0) > 0 {
                            C.pageBg.ignoresSafeArea(edges: .bottom)
                        }
                    }

                    .offset(y: UIConfig.num("tabBarDrop", 0))
                    .transition(.move(edge: .bottom))
            }
        }

        .background(C.pageBg.ignoresSafeArea())

        .overlay(CallOverlay())

        .sheet(isPresented: Binding(
            get: { !(UserDefaults.standard.string(forKey: "chris.lastCrash") ?? "").isEmpty && !shownCrash },
            set: { v in shownCrash = true })) {
                CrashLogView()
        }

        .overlay(CallDialogOverlay())

        .overlay(OtherLoginCard().environmentObject(app))

        .sheet(item: $app.payScan) { info in
            PayConfirmPage(target: info, scanText: app.payScanText)
                .environmentObject(app)
        }

        .sheet(isPresented: Binding(get: { app.scanCardUser != nil },
                                    set: { if !$0 { app.scanCardUser = nil } })) {
            if let u = app.scanCardUser {
                NavigationStack {
                    ContactCardView(user: u,
                                    onOpenChat: { chat in
                                        app.scanCardUser = nil
                                        app.openChatViaList(chat)
                                    },
                                    onOpenMoments: { _ in app.scanCardUser = nil })
                        .environmentObject(app)
                }
            }
        }

        .fullScreenCover(item: $app.nearbyDropInvite) { invite in
            FaceToFaceFileSheet(rows: [], avatar: "", name: invite.name, mode: .join(invite))
                .environmentObject(app)
        }

        .alert("根据国家规定", isPresented: $realNameGate.alert) {
            Button("去实名认证") { realNameGate.openPage = true }
            Button("取消", role: .cancel) { }
        } message: {
            Text("请先完成实名认证，之后才能使用转账、红包、收付款、零钱等功能。聊天不受影响。")
        }
        .sheet(isPresented: $realNameGate.openPage) {
            RealNameView().environmentObject(app)
        }

        .overlay {
            if musicSheet.open {
                MusicPlayingView()
                    .transition(.move(edge: .bottom))
                    .zIndex(60)
            }
        }
        .animation(.easeOut(duration: 0.22), value: musicSheet.open)

        .fullScreenCover(item: Binding(
            get: { mallSheet.open ? mallSheet.product : nil },
            set: { if $0 == nil { mallSheet.close() } }
        )) { p in
            DDDetailView(product: p,
                         onCart: { mallSheet.close() },
                         onOpenOther: { mallSheet.product = $0 })
                .environmentObject(app)
        }

        .overlay(MiniPlayerBall(hidden: app.openChat != nil || musicSheet.open))

        .fullScreenCover(item: $app.openChat) { c in

            NavigationStack {
                ChatDetailView(chat: c).environmentObject(app)
            }

            .overlay(MiniPlayerBall())

            .overlay {
                if musicSheet.open {
                    MusicPlayingView()
                        .transition(.move(edge: .bottom))
                        .zIndex(60)
                }
            }
            .animation(.easeOut(duration: 0.22), value: musicSheet.open)
        }

        .fullScreenCover(item: $app.openMiniApp) { g in
            GameWebPage(game: g).environmentObject(app)
        }
        .onReceive(NotificationCenter.default.publisher(for: .chrisOpenChat)) { note in
            guard let chatId = note.userInfo?["chatId"] as? String, !chatId.isEmpty else { return }
            CrashCatcher.note("推送", "点通知 chatId=" + chatId)
            Task { @MainActor in

                for _ in 0..<40 {
                    if UIApplication.shared.applicationState == .active { break }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                await app.loadChats()
                CrashCatcher.note("推送", "会话已加载 " + String(app.chats.count) + " 个")

                tab = 0
                app.pendingPushChatId = chatId
            }
        }

        .onChange(of: app.wantChatsTab) { v in
            if v { tab = 0; app.wantChatsTab = false }
        }

        .onReceive(NotificationCenter.default.publisher(for: .chrisOpenPair)) { note in
            guard let code = note.userInfo?["code"] as? String, !code.isEmpty else { return }
            app.pairApproveCode = code
        }

        .task {
            while !Task.isCancelled {
                await app.checkReachability()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }

        .onAppear { CrashCatcher.note("启动", "7 主界面出现") }
    }
}

struct TabBarTouchLayer: UIViewRepresentable {

    var onTap: (CGFloat) -> Void
    var onLongPressBegan: (CGFloat) -> Void
    var onLongPressChanged: (CGFloat) -> Void
    var onLongPressEnded: (CGFloat) -> Void

    var onSlide: (CGFloat) -> Void

    var onSlideEnded: (CGFloat) -> Void

    final class Coord: NSObject, UIGestureRecognizerDelegate {
        var onTap: (CGFloat) -> Void = { _ in }
        var onBegan: (CGFloat) -> Void = { _ in }
        var onChanged: (CGFloat) -> Void = { _ in }
        var onEnded: (CGFloat) -> Void = { _ in }
        var onSlide: (CGFloat) -> Void = { _ in }
        var onSlideEnded: (CGFloat) -> Void = { _ in }

        private var lastPressEnd = Date.distantPast

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let v = g.view else { return }
            if Date().timeIntervalSince(lastPressEnd) < 0.35 { return }
            onTap(g.location(in: v).x)
        }

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard let v = g.view else { return }
            let x = g.location(in: v).x
            switch g.state {
            case .began, .changed:
                onSlide(x)
            case .ended, .cancelled, .failed:
                onSlideEnded(x)
            default:
                break
            }
        }

        @objc func handlePress(_ g: UILongPressGestureRecognizer) {
            guard let v = g.view else { return }
            let x = g.location(in: v).x
            switch g.state {
            case .began:
                onBegan(x)
            case .changed:
                onChanged(x)
            case .ended, .cancelled, .failed:
                lastPressEnd = Date()
                onEnded(x)
            default:
                break
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            let pair = [g, other]
            let panAndPress = pair.contains { $0 is UIPanGestureRecognizer }
                && pair.contains { $0 is UILongPressGestureRecognizer }
            return panAndPress
        }
    }

    func makeCoordinator() -> Coord { Coord() }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = true

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coord.handleTap(_:)))
        v.addGestureRecognizer(tap)

        let press = UILongPressGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coord.handlePress(_:)))

        press.minimumPressDuration = UIConfig.num("tabLoupePress", 0.22)

        press.allowableMovement = 10000
        press.delegate = context.coordinator
        v.addGestureRecognizer(press)

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coord.handlePan(_:)))
        pan.delegate = context.coordinator
        v.addGestureRecognizer(pan)

        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onBegan = onLongPressBegan
        context.coordinator.onChanged = onLongPressChanged
        context.coordinator.onEnded = onLongPressEnded
        context.coordinator.onSlide = onSlide
        context.coordinator.onSlideEnded = onSlideEnded
    }
}

struct TabBar: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Binding var selection: Int
    var badge: Int

    var contactsDot: Bool = false

    var momentsDot: Bool = false

    var meDot: Bool = false

    private var items: [(String, String, String)] {
        [
            ("message", "message.fill", C.tabText0),
            ("person.2", "person.2.fill", C.tabText1),
            ("safari", "safari", C.tabText2),
            ("person.crop.circle", "person.crop.circle.fill", C.tabText3)
        ]
    }

    private func iconFont(_ i: Int) -> Font {
        let def = (i == 0 || i == 1) ? L.tabIcon - 2 : L.tabIcon
        return pf(UIConfig.num("tabIcon\(i)", def))
    }

    private let customKeys = ["tab.chat", "tab.contacts", "tab.discover", "tab.me"]

    private func customSize(_ i: Int) -> CGFloat {
        UIConfig.num("tabIcon\(i)", L.tabIconBox)
    }

    private var selColor: Color {
        C.xingjiOn ? C.green : UIConfig.color("tabSelColor", 0x1A1A1A, 0xEDEDED)
    }
    private var unselColor: Color {
        C.xingjiOn ? C.subLabel : UIConfig.color("tabUnselColor", 0x6B6B6B, 0x8E8E93)
    }

    private func tabIconFont(_ i: Int, on: Bool) -> Font {
        let base = UIConfig.num("tabIcon\(i)", (i == 0 || i == 1) ? L.tabIcon - 2 : L.tabIcon)
        return pf(on ? base + 1.5 : base)
    }

    @State private var barWidth: CGFloat = 0
    @State private var dragX: CGFloat? = nil
    @State private var dragIndex: Int? = nil

    @State private var slideX: CGFloat? = nil
    private let dragHaptic = UIImpactFeedbackGenerator(style: .light)

    private func updateDrag(_ x: CGFloat) {
        guard barWidth > 1, !items.isEmpty else { return }
        let seg = barWidth / CGFloat(items.count)
        let i = min(items.count - 1, max(0, Int(x / seg)))
        if i != dragIndex { dragHaptic.impactOccurred() }
        dragX = x
        dragIndex = i
    }

    private func selectTab(at x: CGFloat) {
        guard barWidth > 1, !items.isEmpty else { return }
        let seg = barWidth / CGFloat(items.count)
        selection = min(items.count - 1, max(0, Int(x / seg)))
    }

    private var tabMaskLayer: some View {

        if scheme == .dark && !C.xingjiOn {
            return AnyView(HarmonyDarkMask(strength: 0.98))
        }
        let fill = C.xingjiOn
            ? C.tabBg
            : (UIConfig.colorIfSet("tabBarColor") ?? UIConfig.colorIfSet("tabBg") ?? C.tabBg)

        let glassOn = UIConfig.num("tabGlass", 1) > 0
        if glassOn {
            return AnyView(ZStack {

                let blurA = UIConfig.num("tabBarBlur", 0.9)
                if blurA > 0 {
                    Rectangle()
                        .fill(.bar)
                        .opacity(max(0, min(1, blurA)))
                }
                GlassBackground(shape: Rectangle(),
                                opacity: UIConfig.num("tabBarGlass", 0.9),

                                edgeAlpha: UIConfig.num("tabEdgeAlpha", 0.5),
                                shadow: false,
                                seed: 0.55,
                                native: true)

                fill.opacity(UIConfig.num("tabBarOpaque", 0.10))
            })
        }
        let glass = UIConfig.num("tabGlass", 1) > 0 ? UIConfig.num("tabGlassAlpha", 0.5) : 0
        return AnyView(ZStack {
            fill
                .opacity(UIConfig.num("tabBarOpaque", 0.32))
            Rectangle().fill(.bar)
                .opacity(glass)
        })
    }

    private var dropH: CGFloat { max(0, UIConfig.num("tabBarDrop", 0)) }

    @ViewBuilder
    private func magnifier(_ i: Int, x: CGFloat) -> some View {
        let d: CGFloat = UIConfig.num("tabLoupeSize", 64)
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().stroke(LinearGradient(colors: [Color.white.opacity(0.75),
                                                    Color.white.opacity(0.22)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1)
            if i < items.count {
                Image(systemName: i == selection ? items[i].1 : items[i].0)
                    .font(.system(size: d * 0.46, weight: .medium))
                    .foregroundColor(selColor)
            }
        }
        .frame(width: d, height: d)
        .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
        .offset(x: x - d / 2, y: -d - 12)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                Button {
                    selection = i
                } label: {
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            if let custom = IconOverrides.custom(customKeys[i]) {

                                if custom.hasPrefix("http") || custom.hasPrefix("/uploads") || custom.hasPrefix("data:") {
                                    RemoteImage(path: custom, template: true)
                                        .frame(width: customSize(i), height: customSize(i))
                                        .foregroundColor(selection == i ? selColor : unselColor)
                                } else {
                                    FlexIcon(custom: custom, size: customSize(i),
                                             color: selection == i ? selColor : unselColor,
                                             symbol: items[i].0)
                                }
                            } else if i == 3, let av = app.me?.avatarPath, !av.isEmpty {

                                Avatar(path: av, size: UIConfig.num("tabAvatar", 24), radius: 0, circle: true)
                                    .overlay(Circle().stroke(selection == i ? selColor : Color.clear, lineWidth: 1.5))
                            } else {
                                Image(systemName: selection == i ? items[i].1 : items[i].0)
                                    .font(tabIconFont(i, on: selection == i))
                                    .frame(width: L.tabIconBox, height: L.tabIconBox)
                            }
                            if i == 0 && badge > 0 {
                                Text(badge > 99 ? "99+" : "\(badge)")
                                    .font(pf(11, .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 3)
                                    .frame(minWidth: 15, minHeight: 15)
                                    .background(Capsule().fill(C.red))
                                    .offset(x: 5, y: -3)
                            }

                            if i == 2 && momentsDot {
                                Circle()
                                    .fill(C.red)
                                    .frame(width: 9, height: 9)
                                    .overlay(Circle().stroke(C.tabBg, lineWidth: 1.5))
                                    .offset(x: 4, y: -2)
                            }

                            if i == 1 && contactsDot {
                                Circle()
                                    .fill(C.red)
                                    .frame(width: 9, height: 9)
                                    .overlay(Circle().stroke(C.tabBg, lineWidth: 1.5))
                                    .offset(x: 4, y: -2)
                            }

                            if i == 3 && meDot {
                                Circle()
                                    .fill(C.red)
                                    .frame(width: 9, height: 9)
                                    .overlay(Circle().stroke(C.tabBg, lineWidth: 1.5))
                                    .offset(x: 4, y: -2)
                            }
                        }
                        .frame(width: L.tabIconBox + 10, height: L.tabIconBox + 3)
                        Text(items[i].2)
                            .font(pf(UIConfig.num("tabLabel", L.tabLabel),
                                     selection == i ? .medium : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .frame(height: max(12, L.tabLabel + 2))
                    }
                    .foregroundColor(selection == i ? selColor : unselColor)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: L.tabH)

        .allowsHitTesting(false)

        .background(alignment: .leading) {
            if barWidth > 1, !items.isEmpty {
                let seg = barWidth / CGFloat(items.count)
                let w = max(0, seg - UIConfig.num("tabSliderInset", 10))
                let cx = slideX ?? dragX ?? (seg * (CGFloat(selection) + 0.5))
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)

                    .opacity(UIConfig.num("tabSliderAlpha", 0.55))
                    .overlay(

                        Capsule(style: .continuous)
                            .stroke(LinearGradient(colors: [Color.white.opacity(0.70),
                                                            Color.white.opacity(0.16)],
                                                   startPoint: .top, endPoint: .bottom),
                                    lineWidth: 0.9)
                    )
                    .shadow(color: .black.opacity(0.10), radius: 6, y: 3)
                    .frame(width: w, height: max(0, L.tabH - UIConfig.num("tabSliderVInset", 14)))
                    .offset(x: cx - w / 2)

                    .animation(.spring(response: 0.28, dampingFraction: 0.84), value: selection)
                    .animation(nil, value: dragX)
            }
        }
        .background(

            tabMaskLayer
                .ignoresSafeArea(edges: .bottom)
        )

        .background(GeometryReader { g in
            Color.clear
                .onAppear { barWidth = g.size.width }
                .onChange(of: g.size.width) { w in barWidth = w }
        })

        .overlay(alignment: .top) {
            tabMaskLayer
                .frame(height: dropH)
                .offset(y: -dropH)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())

        .overlay {
            TabBarTouchLayer(
                onTap: { x in
                    selectTab(at: x)
                },
                onLongPressBegan: { x in
                    updateDrag(x)
                    dragHaptic.impactOccurred()
                },
                onLongPressChanged: { x in
                    updateDrag(x)
                },
                onLongPressEnded: { x in
                    updateDrag(x)
                    if let i = dragIndex, i < items.count { selection = i }
                    withAnimation(.easeOut(duration: 0.16)) {
                        dragX = nil
                        dragIndex = nil
                    }
                },
                onSlide: { x in

                    slideX = x
                },
                onSlideEnded: { x in

                    let seg = barWidth > 1 ? barWidth / CGFloat(items.count) : 0
                    if seg > 0 {
                        selection = min(items.count - 1, max(0, Int(x / seg)))
                    }
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        slideX = nil
                    }
                }
            )
        }
        .overlay(alignment: .bottomLeading) {
            if let i = dragIndex, let x = dragX {
                magnifier(i, x: x)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
    }
}

struct NavBar<Right: View>: View {
    let title: String

    let titleView: AnyView?
    let back: (() -> Void)?
    let onLongPressTitle: (() -> Void)?

    let leftExtra: AnyView?

    var floating: Bool = true

    var leftExtraGlass: Bool = true
    private let right: Right

    init(title: String,
         back: (() -> Void)? = nil,
         onLongPressTitle: (() -> Void)? = nil,
         titleView: AnyView? = nil,
         leftExtra: AnyView? = nil,
         floating: Bool = true,
         leftExtraGlass: Bool = true,
         @ViewBuilder right: () -> Right) {
        self.title = title
        self.titleView = titleView
        self.back = back
        self.onLongPressTitle = onLongPressTitle
        self.leftExtra = leftExtra
        self.floating = floating
        self.leftExtraGlass = leftExtraGlass
        self.right = right()
    }

    private var useFloating: Bool { floating && UIConfig.num("navFloating", 1) > 0 }

    var body: some View {
        ZStack {
            if useFloating {

                if !title.isEmpty {
                    Group {
                        if let titleView { titleView } else { titleText }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background {
                        GlassBackground(shape: Capsule(),
                                        shadow: true,
                                        seed: 0.30,
                                        darkEdgeOff: true)
                    }
                }
            } else {

                if let titleView { titleView } else { titleText }

                if titleView == nil && titleStroke > 0 {
                    titleText.offset(x: titleStroke)
                }
            }

            HStack(spacing: 0) {
                if let back = back {
                    Button(action: back) {
                        FlexIcon(custom: IconOverrides.custom("nav.back"), size: 20,
                                 color: C.label, symbol: "chevron.left", weight: .medium)
                            .frame(width: useFloating ? 36 : 44, height: useFloating ? 36 : L.navH)
                            .background {
                                if useFloating {
                                    GlassBackground(shape: Circle(),
                                                    shadow: true,
                                                    seed: 0.10,
                                                    darkEdgeOff: true)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, useFloating ? 10 : 0)
                }
                if let leftExtra = leftExtra {
                    if useFloating && leftExtraGlass {

                        leftExtra
                            .frame(height: 36)
                            .padding(.horizontal, 6)
                            .background { GlassBackground(shape: Capsule(), shadow: true, seed: 0.55) }
                            .padding(.leading, 6)
                    } else {
                        leftExtra
                            .frame(height: useFloating ? 36 : L.navH)
                            .padding(.leading, useFloating ? 6 : 0)
                    }
                }
                Spacer(minLength: 0)
                if useFloating {
                    right
                        .frame(height: 36)
                        .background {
                            GlassBackground(shape: Capsule(),
                                            shadow: true,
                                            seed: 0.80,
                                            darkEdgeOff: true)
                        }
                        .padding(.trailing, 10)
                } else {
                    right
                }
            }
        }
        .frame(height: L.navH)
    }

    private var titleText: some View {
        Text(title)
            .font(pf(titleSize, weight))
            .foregroundColor(C.label)
            .onLongPressGesture { onLongPressTitle?() }
    }

    private var titleSize: CGFloat {
        let base = UIConfig.num("navTitle", 17)
        return title == "发现" ? base - 1 : base
    }

    private var weight: Font.Weight { .semibold }

    private var titleStroke: CGFloat { UIConfig.num("navTitleStroke", 0) }
}

extension NavBar where Right == EmptyView {
    init(title: String,
         back: (() -> Void)? = nil,
         onLongPressTitle: (() -> Void)? = nil,
         titleView: AnyView? = nil,
         leftExtra: AnyView? = nil,
         floating: Bool = true) {
        self.init(title: title, back: back, onLongPressTitle: onLongPressTitle,
                  titleView: titleView, leftExtra: leftExtra, floating: floating) { EmptyView() }
    }
}

struct SearchBoxCenter: View {
    @Binding var text: String
    var externalFocus: FocusState<Bool>.Binding? = nil
    @FocusState private var localFocus: Bool

    private var focused: Bool { externalFocus?.wrappedValue ?? localFocus }

    private var centered: Bool { text.isEmpty && !focused }

    @ViewBuilder
    private var field: some View {
        let tf = TextField("", text: $text)
            .font(pf(16))
            .foregroundColor(C.label)
            .multilineTextAlignment(centered ? .center : .leading)
        if let externalFocus = externalFocus {
            tf.focused(externalFocus)
        } else {
            tf.focused($localFocus)
        }
    }

    var body: some View {
        HStack(spacing: centered ? 3 : 5) {
            SVGIcon(markup: I.searchSmall, size: 16, color: C.searchIcon)

            ZStack(alignment: centered ? .center : .leading) {
                if text.isEmpty {
                    Text(Tr("搜索"))
                        .font(pf(16))
                        .foregroundColor(C.searchIcon)
                }
                field
            }
            .frame(maxWidth: centered ? 46 : .infinity)
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .padding(.leading, centered ? 28 : 9)
        .padding(.trailing, centered ? 18 : 9)
        .frame(height: L.searchBoxH)
        .background(

            GlassBackground(shape: Capsule(style: .continuous),
                            opacity: UIConfig.num("searchGlassAlpha", 0.55),
                            edgeAlpha: UIConfig.num("searchGlassEdge", 0))
        )
    }
}

struct SearchBoxLeft: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: L.v(5, 1.8, 8)) {
            SVGIcon(markup: I.searchBig, size: 16, color: C.searchIcon2)
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(Tr("搜索"))
                        .font(pf(15))
                        .foregroundColor(C.searchIcon2)
                }
                TextField("", text: $text)
                    .font(pf(15))
                    .foregroundColor(C.label)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .frame(height: L.searchBoxH)
        .background(

            GlassBackground(shape: Capsule(style: .continuous),
                            opacity: UIConfig.num("searchGlassAlpha", 0.55),
                            edgeAlpha: UIConfig.num("searchGlassEdge", 0))
        )
    }
}

struct MenuRow: View {
    let icon: String
    var iconColor: Color = C.green

    var padLeading: CGFloat = 18
    let title: String
    var detail: String = ""
    var showArrow: Bool = true
    var badge: Bool = false
    var thumb: String = ""
    var onTap: (() -> Void)? = nil

    var clearBg: Bool = false

    var iconTile: Bool = false

    var sf: String = ""

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: L.menuGap) {

                if iconTile {

                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(iconColor)
                        if !sf.isEmpty {
                            Image(systemName: sf)
                                .font(.system(size: L.menuIcon * 0.60, weight: .semibold))
                                .foregroundColor(.white)
                        } else {
                            SVGIcon(markup: icon, size: L.menuIcon * 0.78, color: .white)
                        }
                    }
                    .frame(width: L.menuIcon, height: L.menuIcon)
                } else if !sf.isEmpty {
                    Image(systemName: sf)
                        .font(.system(size: L.menuIcon * 0.82, weight: .regular))
                        .foregroundColor(iconColor)
                        .frame(width: L.menuIcon, height: L.menuIcon)
                } else if UIConfig.num("menuIconAnim", 0) > 0,
                          icon.hasPrefix("anim:"),
                   let kind = MenuIconKind(rawValue: String(icon.dropFirst(5))) {
                    AnimatedMenuIcon(kind: kind, size: L.menuIcon)
                        .frame(width: L.menuIcon, height: L.menuIcon)
                } else {
                    SVGIcon(markup: icon, size: L.menuIcon * 1.13, color: iconColor)
                        .frame(width: L.menuIcon, height: L.menuIcon)
                }

                Text(title)
                    .font(pf(L.menuTextSize))
                    .foregroundColor(C.label)

                Spacer(minLength: 0)

                if !detail.isEmpty {
                    Text(detail).font(pf(15)).foregroundColor(C.subLabel)
                }
                if !thumb.isEmpty {
                    ZStack(alignment: .topTrailing) {
                        RemoteImage(path: thumb)
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        if badge {
                            Circle().fill(C.red).frame(width: 9, height: 9).offset(x: 4.5, y: -4.5)
                        }
                    }
                    .frame(width: 32, height: 32)
                    .padding(.trailing, -8)
                }
                if showArrow {
                    Chevron(size: 9, line: 1.6)
                        .padding(.trailing, 3)
                }
            }
            .padding(.leading, padLeading)
            .padding(.trailing, L.menuPadR)
            .frame(height: L.menuH)
            .background(clearBg ? Color.clear : C.cardBg)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuPressStyle())
    }
}

struct MenuPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.gray.opacity(0.16) : Color.clear)
    }
}

struct GroupCard<Content: View>: View {
    let content: Content

    var glass: Bool = false

    var bg: Color? = nil
    init(glass: Bool = false, bg: Color? = nil, @ViewBuilder content: () -> Content) {
        self.glass = glass
        self.bg = bg
        self.content = content()
    }

    var body: some View {
        if glass {
            VStack(spacing: 0) { content }
                .background {
                    ZStack {
                        GlassBackground(shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
                                        opacity: UIConfig.num("meGlassAlpha", 0.62),
                                        edgeAlpha: UIConfig.num("meGlassEdge", 0.55),
                                        shadow: true,
                                        seed: 0.42,
                                        native: true)
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(C.cardBg.opacity(0.42))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, UIConfig.num("meGlassInset", 12))
                .padding(.bottom, 10)
        } else {
            VStack(spacing: 0) { content }
                .background(bg ?? C.cardBg)
                .overlay {
                    if C.xingjiOn {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(C.hairline, lineWidth: 0.5)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: C.xingjiOn ? 16 : 0,
                                            style: .continuous))
                .padding(.horizontal, C.xingjiOn ? 12 : 0)
                .padding(.bottom, C.xingjiOn ? 10 : 0)
        }
    }
}

struct GroupGap: View {

    var bg: Color? = nil
    var body: some View {

        ZStack(alignment: .bottom) {
            HairLine()
            Rectangle().fill(bg ?? C.pageBg).frame(height: L.groupGap)
            HairLine()
        }
    }
}
