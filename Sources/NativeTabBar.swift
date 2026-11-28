import SwiftUI
import UIKit

private enum NativeTabBarVisual {
    static var normalInk: Color { Color.dyn(0x757D78, 0x8E8E93) }
    static var selectedInk: Color { Color.dyn(0x117A58, 0x42C693) }
    static let badge = UIColor.systemRed
}

private final class BrandTabBadgeView: UIView {
    enum Kind {
        case count
        case dot
        case world
    }

    private let gradient = CAGradientLayer()
    private let highlight = CAShapeLayer()
    private let label = UILabel()
    private var kind: Kind = .dot
    private var ringColor = UIColor.black

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = false
        gradient.startPoint = CGPoint(x: 0.18, y: 0.08)
        gradient.endPoint = CGPoint(x: 0.82, y: 1)
        layer.insertSublayer(gradient, at: 0)

        label.textAlignment = .center
        label.textColor = .white
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.72
        addSubview(label)

        highlight.fillColor = UIColor.white.withAlphaComponent(0.24).cgColor
        layer.addSublayer(highlight)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(kind: Kind, count: Int = 0, ringColor: UIColor) {
        self.kind = kind
        self.ringColor = ringColor
        switch kind {
        case .count:
            label.isHidden = false
            label.text = count > 99 ? "•••" : "\(count)"
            label.font = .systemFont(ofSize: 9.5, weight: .bold)
            gradient.colors = [
                UIColor(red: 1.00, green: 0.23, blue: 0.19, alpha: 1).cgColor,
                UIColor(red: 0.95, green: 0.16, blue: 0.12, alpha: 1).cgColor
            ]
            layer.cornerRadius = 9
            layer.borderWidth = 1.2
            layer.borderColor = ringColor.cgColor
            layer.shadowOpacity = 0
        case .dot:
            label.isHidden = true
            gradient.colors = [
                UIColor(red: 1.00, green: 0.23, blue: 0.19, alpha: 1).cgColor,
                UIColor(red: 0.95, green: 0.16, blue: 0.12, alpha: 1).cgColor
            ]
            layer.cornerRadius = 4.25
            layer.borderWidth = 1.2
            layer.borderColor = ringColor.cgColor
            layer.shadowOpacity = 0
        case .world:
            label.isHidden = true
            gradient.colors = [
                UIColor(red: 1.00, green: 0.48, blue: 0.51, alpha: 1).cgColor,
                UIColor(red: 0.90, green: 0.13, blue: 0.24, alpha: 1).cgColor,
                UIColor(red: 0.66, green: 0.03, blue: 0.15, alpha: 1).cgColor
            ]
            layer.cornerRadius = 5
            layer.borderWidth = 1.2
            layer.borderColor = ringColor.cgColor
            layer.shadowColor = UIColor(red: 0.90, green: 0.13, blue: 0.24, alpha: 1).cgColor
            layer.shadowOpacity = 0.34
            layer.shadowRadius = 4
            layer.shadowOffset = CGSize(width: 0, height: 1.5)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        gradient.cornerRadius = layer.cornerRadius
        label.frame = bounds.insetBy(dx: 2, dy: 0)
        let highlightFrame = CGRect(
            x: max(1.5, bounds.width * 0.16),
            y: max(1.2, bounds.height * 0.12),
            width: max(2, bounds.width * 0.22),
            height: max(1.4, bounds.height * 0.14)
        )
        highlight.path = UIBezierPath(ovalIn: highlightFrame).cgPath
        highlight.isHidden = kind != .world
    }
}

private final class CompactDotTabBar: UITabBar {
    var dotIndexes: Set<Int> = [] {
        didSet { setNeedsLayout() }
    }

    var clearsNativeBackdrop = false {
        didSet { updateNativeBackdropVisibility() }
    }

    private var dotViews: [Int: UIView] = [:]
    var badgeCount: Int = 0 {
        didSet { setNeedsLayout() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateNativeBackdropVisibility()
        let slot = bounds.width / 5
        for index in 0..<5 {
            let dot = dotViews[index] ?? {
                let view = BrandTabBadgeView()
                view.layer.cornerRadius = 4
                addSubview(view)
                dotViews[index] = view
                return view
            }()
            let badge = dot as! BrandTabBadgeView
            let centerX = slot * (CGFloat(index) + 0.5)
            if index == 0, badgeCount > 0 {
                let title = badgeCount > 99 ? "•••" : "\(badgeCount)"
                let width: CGFloat = title.count > 2 ? 28 : (title.count > 1 ? 23 : 18)
                badge.frame = CGRect(x: centerX + 8, y: 2,
                                     width: width, height: 18)
                badge.apply(kind: .count, count: badgeCount,
                            ringColor: UIColor(C.tabBg))
                badge.isHidden = false
                bringSubviewToFront(badge)
                continue
            }
            let isWorld = index == 3 && dotIndexes.contains(index)
            let side: CGFloat = isWorld ? 10 : 8.5
            badge.frame = CGRect(x: centerX + (isWorld ? 9 : 10),
                                 y: 4,
                                 width: side, height: side)
            badge.apply(kind: isWorld ? .world : .dot,
                        ringColor: UIColor(C.tabBg))
            badge.isHidden = !dotIndexes.contains(index)
            guard !dot.isHidden else { continue }
            bringSubviewToFront(dot)
        }
    }

    private func updateNativeBackdropVisibility() {
        /* 原生 TabBar 背板负责系统玻璃，不覆盖图标内容。 */
        for child in subviews {
            let typeName = String(describing: type(of: child))
            guard typeName.contains("BarBackground") else { continue }
            child.isHidden = clearsNativeBackdrop
        }
    }
}

@MainActor
fileprivate final class TabAvatarLoader: ObservableObject {
    static let shared = TabAvatarLoader()

    @Published private(set) var revision = 0

    private var images: [String: UIImage] = [:]
    private var inFlight: Set<String> = []
    private var retryTasks: [String: Task<Void, Never>] = [:]

    private init() {}

    func image(for value: String) -> UIImage? {
        if let image = images[value] { return image }
        guard let cached = ImageStore.shared.get(value) else { return nil }
        images[value] = cached
        return cached
    }

    func prepare(_ value: String) {
        guard !value.isEmpty, images[value] == nil, !inFlight.contains(value) else { return }
        if let cached = ImageStore.shared.get(value) {
            images[value] = cached
            revision &+= 1
            return
        }
        guard let url = API.shared.assetURL(value) else { return }
        inFlight.insert(value)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.inFlight.remove(value) }
            do {
                let data = try await API.shared.assetData(url)
                guard !Task.isCancelled, let image = UIImage(data: data) else {
                    self.scheduleRetry(value)
                    return
                }
                ImageStore.shared.put(value, image)
                ImageStore.shared.diskWrite(value, data)
                self.images[value] = image
                self.revision &+= 1
            } catch {
                self.scheduleRetry(value)
            }
        }
    }

    private func scheduleRetry(_ value: String) {
        retryTasks[value]?.cancel()
        retryTasks[value] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.retryTasks.removeValue(forKey: value)
            self.prepare(value)
        }
    }
}

/// 只替换底栏；页面、顶栏、导航和键盘布局继续使用 B2103 原实现。
struct NativeTabBar: UIViewRepresentable {
    @Binding var selection: Int
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @StateObject private var avatarLoader = TabAvatarLoader.shared
    let badge: Int
    let contactsDot: Bool
    let momentsDot: Bool
    let meDot: Bool
    let avatarPath: String

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeUIView(context: Context) -> UITabBar {
        let bar = CompactDotTabBar()
        bar.delegate = context.coordinator
        bar.itemPositioning = .fill
        bar.items = [
            UITabBarItem(title: C.tabText0,
                         image: UIImage(systemName: "message")?
                            .withRenderingMode(.alwaysTemplate),
                         selectedImage: UIImage(systemName: "message.fill")?
                            .withRenderingMode(.alwaysTemplate)),
            UITabBarItem(title: C.tabText1,
                         image: UIImage(systemName: "person.2")?
                            .withRenderingMode(.alwaysTemplate),
                         selectedImage: UIImage(systemName: "person.2.fill")?
                            .withRenderingMode(.alwaysTemplate)),
            UITabBarItem(title: C.tabTextVideo,
                         image: UIImage(systemName: "play.rectangle")?
                            .withRenderingMode(.alwaysTemplate),
                         selectedImage: UIImage(systemName: "play.rectangle.fill")?
                            .withRenderingMode(.alwaysTemplate)),
            UITabBarItem(title: C.tabText2,
                         image: UIImage(systemName: "safari")?
                            .withRenderingMode(.alwaysTemplate),
                         selectedImage: UIImage(systemName: "safari.fill")?
                            .withRenderingMode(.alwaysTemplate)),
            UITabBarItem(title: C.tabText3,
                         image: UIImage(systemName: "person.crop.circle")?
                            .withRenderingMode(.alwaysTemplate),
                         selectedImage: UIImage(systemName: "person.crop.circle.fill")?
                            .withRenderingMode(.alwaysTemplate))
        ]
        applyColors(bar)
        refresh(bar)
        return bar
    }

    func updateUIView(_ bar: UITabBar, context: Context) {
        context.coordinator.selection = $selection
        applyColors(bar)
        let titles = [C.tabText0, C.tabText1, C.tabTextVideo, C.tabText2, C.tabText3]
        if let items = bar.items, items.count == titles.count {
            for index in titles.indices where items[index].title != titles[index] {
                items[index].title = titles[index]
            }
            bar.setNeedsLayout()
        }
        if let item = bar.items?[safe: selection], bar.selectedItem !== item {
            bar.selectedItem = item
        }
        avatarLoader.prepare(avatarPath)
        context.coordinator.applyAvatar(
            in: bar,
            loader: avatarLoader,
            revision: avatarLoader.revision,
            avatarPath: avatarPath,
            selected: selection == 4
        )
        refresh(bar)
    }

    private func applyColors(_ bar: UITabBar) {
        bar.tintColor = UIColor(NativeTabBarVisual.selectedInk)
        bar.unselectedItemTintColor = UIColor(NativeTabBarVisual.normalInk)

        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundEffect = nil
        let themed = UIConfig.colorIfSet("tabBarColor")
            ?? UIConfig.colorIfSet("tabBg")
            ?? C.tabBg
        appearance.backgroundColor = UIColor(themed)
        bar.isOpaque = true
        let normalTitle: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(NativeTabBarVisual.normalInk),
            .font: pfUIFont(10, .medium)
        ]
        let selectedTitle: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(NativeTabBarVisual.selectedInk),
            .font: pfUIFont(10, .semibold)
        ]
        let selectedMyTitle: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(NativeTabBarVisual.selectedInk),
            .font: pfUIFont(10, .semibold)
        ]
        let normalIcon = UIColor(NativeTabBarVisual.normalInk)
        let selectedIcon = UIColor(NativeTabBarVisual.selectedInk)
        for itemAppearance in [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance
        ] {
            itemAppearance.normal.iconColor = normalIcon
            itemAppearance.normal.titleTextAttributes = normalTitle
            itemAppearance.selected.iconColor = selectedIcon
            itemAppearance.selected.titleTextAttributes = selectedTitle
        }
        appearance.stackedLayoutAppearance.normal.badgeBackgroundColor = NativeTabBarVisual.badge
        appearance.stackedLayoutAppearance.selected.badgeBackgroundColor = NativeTabBarVisual.badge
        appearance.inlineLayoutAppearance.normal.badgeBackgroundColor = NativeTabBarVisual.badge
        appearance.inlineLayoutAppearance.selected.badgeBackgroundColor = NativeTabBarVisual.badge
        appearance.compactInlineLayoutAppearance.normal.badgeBackgroundColor = NativeTabBarVisual.badge
        appearance.compactInlineLayoutAppearance.selected.badgeBackgroundColor = NativeTabBarVisual.badge
        appearance.shadowColor = UIColor.separator.withAlphaComponent(0.28)
        if let items = bar.items, items.count == 5 {
            items[4].setTitleTextAttributes(normalTitle, for: .normal)
            items[4].setTitleTextAttributes(selectedMyTitle, for: .selected)
        }
        if scheme == .dark {
            appearance.selectionIndicatorImage = UIImage()
            bar.selectionIndicatorImage = UIImage()
        }
        if #available(iOS 26.0, *) {
            if #unavailable(iOS 27.0) {
                let offset = UIOffset(horizontal: 0, vertical: 8)
                appearance.stackedLayoutAppearance.selected.titlePositionAdjustment = offset
                appearance.inlineLayoutAppearance.selected.titlePositionAdjustment = offset
                appearance.compactInlineLayoutAppearance.selected.titlePositionAdjustment = offset
            }
        }
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.isTranslucent = !reduceTransparency
        (bar as? CompactDotTabBar)?.clearsNativeBackdrop = false
    }

    private func refresh(_ bar: UITabBar) {
        guard let items = bar.items, items.count == 5 else { return }
        items[0].badgeValue = badge > 0 ? (badge > 99 ? "99+" : "\(badge)") : nil
        items[1].badgeValue = contactsDot ? "" : nil
        items[2].badgeValue = nil
        items[3].badgeValue = momentsDot ? "" : nil
        items[4].badgeValue = meDot ? "" : nil
        items.forEach { $0.badgeColor = NativeTabBarVisual.badge }
        if let bar = bar as? CompactDotTabBar {
            bar.badgeCount = 0
            bar.dotIndexes = []
            bar.setNeedsLayout()
        }
    }

    final class Coordinator: NSObject, UITabBarDelegate {
        var selection: Binding<Int>
        private let selectionFeedback = UISelectionFeedbackGenerator()
        private var appliedAvatarKey = ""
        private let systemMyImage = UIImage(systemName: "person.crop.circle")?
            .withRenderingMode(.alwaysTemplate)
        private let systemMySelected = UIImage(systemName: "person.crop.circle.fill")?
            .withRenderingMode(.alwaysTemplate)

        init(selection: Binding<Int>) {
            self.selection = selection
        }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard let index = tabBar.items?.firstIndex(where: { $0 === item }) else { return }
            selectionFeedback.prepare()
            selectionFeedback.selectionChanged()
            selection.wrappedValue = index
        }

        fileprivate func applyAvatar(in bar: UITabBar, loader: TabAvatarLoader,
                                     revision: Int, avatarPath: String,
                                     selected: Bool) {
            guard let items = bar.items, items.count == 5 else { return }
            let key = "\(revision)|\(avatarPath)|\(selected ? 1 : 0)"
            guard key != appliedAvatarKey else { return }

            guard !avatarPath.isEmpty, let avatar = loader.image(for: avatarPath) else {
                if avatarPath.isEmpty {
                    items[4].image = systemMyImage
                    items[4].selectedImage = systemMySelected
                    appliedAvatarKey = key
                }
                return
            }

            let circled = circularAvatar(avatar, selected: selected)
            items[4].image = circled.withRenderingMode(.alwaysOriginal)
            items[4].selectedImage = circled.withRenderingMode(.alwaysOriginal)
            appliedAvatarKey = key
        }

        private func circularAvatar(_ image: UIImage, selected: Bool) -> UIImage {
            let side: CGFloat = 25
            let size = CGSize(width: side, height: side)
            return UIGraphicsImageRenderer(size: size).image { context in
                let inset: CGFloat = selected ? 1.4 : 0
                let imageRect = CGRect(origin: .zero, size: size)
                    .insetBy(dx: inset, dy: inset)
                let path = UIBezierPath(ovalIn: imageRect)
                context.cgContext.saveGState()
                path.addClip()
                let scale = max(imageRect.width / max(1, image.size.width),
                                imageRect.height / max(1, image.size.height))
                let drawSize = CGSize(width: image.size.width * scale,
                                      height: image.size.height * scale)
                image.draw(in: CGRect(x: imageRect.midX - drawSize.width / 2,
                                      y: imageRect.midY - drawSize.height / 2,
                                      width: drawSize.width,
                                      height: drawSize.height))
                context.cgContext.restoreGState()
                if selected {
                    let ring = UIBezierPath(
                        ovalIn: CGRect(origin: .zero, size: size)
                            .insetBy(dx: 0.75, dy: 0.75)
                    )
                    UIColor(NativeTabBarVisual.selectedInk).setStroke()
                    ring.lineWidth = 1.5
                    ring.stroke()
                }
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
