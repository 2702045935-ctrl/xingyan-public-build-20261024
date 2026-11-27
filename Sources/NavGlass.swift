import SwiftUI

import SwiftUI
import UIKit

struct TopScrollKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct TopGlassBar: View {
    var scrolled: CGFloat

    var fallback: Color

    var offset: CGFloat = 80

    var always: Bool = false
    var matchFallback: Bool = false
    var matchDarkBackground: Bool = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let blur = UIConfig.num("chatsNavGlassAlpha", 1)

        let mask = UIConfig.num("chatsNavMaskAlpha", 0)

        let raw = min(1, max(0, scrolled / max(1, offset)))

        let t = always ? 1 : pow(raw, 0.8)
        if t > 0.01 {

            Group {
                if matchFallback || (matchDarkBackground && scheme == .dark) {
                    fallback
                } else {
                    ZStack {
                        NativePremiumGlassMaterial(dark: scheme == .dark)
                            .opacity(max(0.72, min(1, blur)) * t)
                        fallback.opacity(0.08 * t)
                        if let maskColor = UIConfig.colorIfSet("chatsNavMaskColor") {
                            maskColor.opacity(max(0, min(1, mask)) * t)
                        }
                    }
                }
            }
            .ignoresSafeArea(edges: .top)

            .allowsHitTesting(false)
        }
    }
}

#if canImport(UIKit)
private final class SpecularEffectView: UIVisualEffectView {
    private let topSheen = CAGradientLayer()
    private let diagonalSheen = CAGradientLayer()
    private let lowerShade = CAGradientLayer()
    private var isDark = true

    init(effect: UIVisualEffect?, dark: Bool) {
        self.isDark = dark
        super.init(effect: effect)
        isUserInteractionEnabled = false
        contentView.layer.masksToBounds = true
        contentView.layer.cornerCurve = .continuous
        contentView.layer.addSublayer(diagonalSheen)
        contentView.layer.addSublayer(topSheen)
        contentView.layer.addSublayer(lowerShade)
        configureDirection()
        applyColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setDark(_ dark: Bool) {
        guard isDark != dark else { return }
        isDark = dark
        applyColors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        diagonalSheen.frame = bounds
        topSheen.frame = CGRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: min(108, max(28, bounds.height * 0.36))
        )
        let shadeHeight = min(40, max(18, bounds.height * 0.20))
        lowerShade.frame = CGRect(
            x: 0,
            y: max(0, bounds.height - shadeHeight),
            width: bounds.width,
            height: shadeHeight
        )
    }

    private func configureDirection() {
        topSheen.startPoint = CGPoint(x: 0.5, y: 0)
        topSheen.endPoint = CGPoint(x: 0.5, y: 1)
        topSheen.locations = [0, 0.32, 1]

        diagonalSheen.startPoint = CGPoint(x: 0, y: 0)
        diagonalSheen.endPoint = CGPoint(x: 0.72, y: 1)
        diagonalSheen.locations = [0, 0.32, 0.78]

        lowerShade.startPoint = CGPoint(x: 0.5, y: 0)
        lowerShade.endPoint = CGPoint(x: 0.5, y: 1)
        lowerShade.locations = [0, 0.7, 1]
    }

    private func applyColors() {
        topSheen.colors = [
            UIColor.white.withAlphaComponent(isDark ? 0.13 : 0.46).cgColor,
            UIColor.white.withAlphaComponent(isDark ? 0.035 : 0.12).cgColor,
            UIColor.clear.cgColor
        ]
        diagonalSheen.colors = [
            UIColor.white.withAlphaComponent(isDark ? 0.045 : 0.16).cgColor,
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(isDark ? 0.045 : 0.015).cgColor
        ]
        lowerShade.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(isDark ? 0.035 : 0.012).cgColor,
            UIColor.black.withAlphaComponent(isDark ? 0.17 : 0.045).cgColor
        ]
    }
}

struct NativePremiumGlassMaterial: UIViewRepresentable {
    let dark: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = SpecularEffectView(effect: effect, dark: dark)
        view.isUserInteractionEnabled = false
        view.contentView.backgroundColor = reduceTransparency
            ? UIColor.secondarySystemBackground
            : (dark ? UIColor.black.withAlphaComponent(0.018)
                    : UIColor.white.withAlphaComponent(0.020))
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        view.effect = effect
        (view as? SpecularEffectView)?.setDark(dark)
        view.contentView.backgroundColor = reduceTransparency
            ? UIColor.secondarySystemBackground
            : (dark ? UIColor.black.withAlphaComponent(0.018)
                    : UIColor.white.withAlphaComponent(0.020))
    }

    private var effect: UIVisualEffect? {
        guard !reduceTransparency else { return nil }
        return UIBlurEffect(style: dark
                            ? .systemUltraThinMaterialDark
                            : .systemUltraThinMaterialLight)
    }
}

struct NativeGlassHeaderMaterial: UIViewRepresentable {
    var forcedDark: Bool? = nil

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    final class Coordinator {
        var token = ""
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIVisualEffectView {
        let dark = forcedDark ?? (scheme == .dark)
        let view = SpecularEffectView(
            effect: Self.visualEffect(dark: dark),
            dark: dark
        )
        view.isUserInteractionEnabled = false
        view.contentView.backgroundColor = .clear
        applyReducedTransparency(to: view)
        context.coordinator.token = Self.effectToken(dark: dark,
                                                     reduced: reduceTransparency)
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        let dark = forcedDark ?? (scheme == .dark)
        let token = Self.effectToken(dark: dark,
                                     reduced: reduceTransparency)
        guard context.coordinator.token != token else { return }
        context.coordinator.token = token
        view.effect = Self.visualEffect(dark: dark)
        (view as? SpecularEffectView)?.setDark(dark)
        applyReducedTransparency(to: view)
    }

    private func applyReducedTransparency(to view: UIVisualEffectView) {
        if reduceTransparency {
            view.effect = nil
            view.backgroundColor = .secondarySystemBackground
        } else {
            view.effect = Self.visualEffect(dark: forcedDark ?? (scheme == .dark))
            view.backgroundColor = .clear
        }
    }

    private static func visualEffect(dark: Bool) -> UIVisualEffect {
        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = false
            effect.tintColor = UIColor.white.withAlphaComponent(dark ? 0.055 : 0.080)
            return effect
        }
        return UIBlurEffect(style: dark
                            ? .systemUltraThinMaterialDark
                            : .systemUltraThinMaterialLight)
    }

    private static func effectToken(dark: Bool, reduced: Bool) -> String {
        if reduced { return "reduced-\(dark)" }
        if #available(iOS 26.0, *) { return "glass-\(dark)" }
        return "material-\(dark)"
    }
}
#endif

#if canImport(UIKit)
/// 顶栏的可靠磨砂层。Liquid Glass 在部分自定义导航容器里几乎透明，
/// 这里直接使用系统材质模糊，保证内容进入标题区后确实被遮住。
struct NativeFrostedHeaderMaterial: UIViewRepresentable {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = SpecularEffectView(
            effect: effect,
            dark: scheme == .dark
        )
        view.isUserInteractionEnabled = false
        view.contentView.backgroundColor = reduceTransparency
            ? UIColor.secondarySystemBackground : .clear
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        view.effect = effect
        (view as? SpecularEffectView)?.setDark(scheme == .dark)
        view.contentView.backgroundColor = reduceTransparency
            ? UIColor.secondarySystemBackground : .clear
    }

    private var effect: UIVisualEffect? {
        guard !reduceTransparency else { return nil }
        return UIBlurEffect(style: scheme == .dark
                            ? .systemMaterialDark
                            : .systemMaterialLight)
    }
}
#endif

struct NativeTopGlassMask: View {
    var active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if !active {
                Color.clear
            } else if reduceTransparency {
                C.pageBg
            } else {
                NativeFrostedHeaderMaterial()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16),
                   value: active)
    }
}

final class NativeTopScrollRegistry {
    static let shared = NativeTopScrollRegistry()
    weak var contacts: UIScrollView?
    weak var discover: UIScrollView?
}

struct NativeChatsTopEdgeChrome: View {
    var scrolled: CGFloat
    var dark: Bool? = nil
    var background: Color? = nil

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var isDark: Bool { dark ?? (scheme == .dark) }

    var body: some View {
        let tint = background ?? (isDark ? C.pageBg : Color(uiColor: .systemBackground))
        Group {
            if reduceTransparency {
                tint
            } else {
                ZStack {
                    NativeGlassHeaderMaterial(forcedDark: isDark)
                    tint.opacity(isDark ? 0.48 : 0.42)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}

#if canImport(UIKit)
struct NativeScrollEdgeElementBridge: UIViewRepresentable {
    let scrollView: () -> UIScrollView?

    final class Coordinator {
        var retryScheduled = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        let edgeShape = UIView()
        edgeShape.backgroundColor = .clear
        edgeShape.isUserInteractionEnabled = false
        edgeShape.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(edgeShape)
        NSLayoutConstraint.activate([
            edgeShape.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            edgeShape.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            edgeShape.topAnchor.constraint(equalTo: view.topAnchor),
            edgeShape.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        attach(to: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        attach(to: view, coordinator: context.coordinator)
    }

    private func attach(to view: UIView, coordinator: Coordinator) {
        guard #available(iOS 26.0, *) else { return }

        let interaction: UIScrollEdgeElementContainerInteraction
        if let current = view.interactions.compactMap({
            $0 as? UIScrollEdgeElementContainerInteraction
        }).first {
            interaction = current
        } else {
            interaction = UIScrollEdgeElementContainerInteraction()
            interaction.edge = .top
            view.addInteraction(interaction)
        }

        interaction.scrollView = scrollView()
        guard interaction.scrollView == nil, !coordinator.retryScheduled else { return }
        coordinator.retryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            coordinator.retryScheduled = false
            guard view.window != nil else { return }
            attach(to: view, coordinator: coordinator)
        }
    }
}
#endif

#if canImport(UIKit)
/// SwiftUI 的 GeometryReader 偏好值在隐藏原生导航栏的页面里偶尔不会随滚动刷新。
/// 顶栏玻璃直接观察实际的 UIScrollView，保证三个主页面使用同一条可靠状态。
struct NativeTopScrollObserver: UIViewRepresentable {
    var onChange: (CGFloat) -> Void
    var onScrollViewReady: ((UIScrollView) -> Void)? = nil

    final class Coordinator {
        weak var scroll: UIScrollView?
        var observation: NSKeyValueObservation?
        var retries = 20
        var onChange: (CGFloat) -> Void = { _ in }
        var onScrollViewReady: ((UIScrollView) -> Void)? = nil

        func attach(_ view: UIView) {
            guard let scroll = Self.findScroll(view) else {
                guard retries > 0 else { return }
                retries -= 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self, weak view] in
                    guard let self, let view else { return }
                    self.attach(view)
                }
                return
            }
            if self.scroll === scroll {
                onChange(max(0, scroll.contentOffset.y))
                return
            }
            observation = nil
            self.scroll = scroll
            onScrollViewReady?(scroll)
            observation = scroll.observe(\.contentOffset, options: [.new]) {
                [weak self] scroll, _ in
                self?.onChange(max(0, scroll.contentOffset.y))
            }
            onChange(max(0, scroll.contentOffset.y))
        }

        private static func findScroll(_ view: UIView) -> UIScrollView? {
            var current: UIView? = view
            while let candidate = current {
                if let scroll = candidate as? UIScrollView { return scroll }
                current = candidate.superview
            }
            return nil
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        context.coordinator.onChange = onChange
        context.coordinator.onScrollViewReady = onScrollViewReady
        context.coordinator.attach(view)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.onScrollViewReady = onScrollViewReady
        context.coordinator.attach(view)
    }
}
#endif

struct ScrollActiveGlassMask: View {
    let base: Color
    let active: Bool
    var activeBaseOpacity: Double? = nil

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack(alignment: .bottom) {
            base
                .opacity(active && !reduceTransparency ? 0 : 1)

            if active && !reduceTransparency {
                ZStack(alignment: .bottom) {
                    NativeGlassHeaderMaterial()
                    base
                        /* 滚动内容进入标题区后必须真正被遮住。
                           保留玻璃的通透感，但浅色页面不能再让下面的文字透出来。 */
                        .opacity(activeBaseOpacity ?? (scheme == .dark ? 0.54 : 0.42))
                    LinearGradient(
                        stops: [
                            .init(color: base.opacity(scheme == .dark ? 0.22 : 0.15),
                                  location: 0),
                            .init(color: base.opacity(scheme == .dark ? 0.12 : 0.08),
                                  location: 0.72),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom)

                    LinearGradient(
                        colors: [
                            Color.white.opacity(scheme == .dark ? 0.055 : 0.13),
                            Color.white.opacity(scheme == .dark ? 0.015 : 0.035),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 46)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: active ? 0.18 : 0.22),
                   value: active)
        .allowsHitTesting(false)
    }
}

struct NativeChromeMaterial: View {
    var opacity: Double = 1
    var liquid: Bool = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), liquid, !reduceTransparency {
            Color.clear
                .glassEffect(.regular, in: Rectangle())
                .opacity(max(0, min(1, opacity)))
                .allowsHitTesting(false)
        } else if reduceTransparency {
            reducedSurface
        } else {
            fallback
        }
        #else
        fallback
        #endif
    }

    private var reducedSurface: some View {
        Rectangle()
            .fill(UIConfig.fixedDark("glassReducedSurface", 0xFAFBF9, 0x1D231F))
            .overlay {
                Rectangle()
                    .stroke(C.hairline.opacity(scheme == .dark ? 0.72 : 0.55),
                            lineWidth: 0.5)
            }
            .opacity(max(0, min(1, opacity)))
            .allowsHitTesting(false)
    }

    private var fallback: some View {
        Rectangle()
            .fill(.bar)
            .opacity(max(0, min(1, opacity)))
            .allowsHitTesting(false)
    }
}

struct TopGlassLine: View {
    var scrolled: CGFloat
    var body: some View {
        Rectangle()
            .fill(C.navLine)
            .frame(height: 0.5)
            .opacity(scrolled > 6 ? 1 : 0)
    }
}

struct NavPlusGlassBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let base = UIConfig.color("navPlusBg", 0x51A969, 0x51A969)
        ZStack {
            Circle().fill(base)
            Circle().fill(
                LinearGradient(colors: [
                    Color.white.opacity(scheme == .dark ? 0.13 : 0.18),
                    Color.clear,
                    Color.black.opacity(scheme == .dark ? 0.10 : 0.07)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            Circle()
                .stroke(Color.white.opacity(scheme == .dark ? 0.16 : 0.24),
                        lineWidth: 0.7)
        }
        .shadow(color: Color.black.opacity(scheme == .dark ? 0.30 : 0.16),
                radius: 8, y: 4)
    }
}

struct NativeGlassCircleBackground: View {
    var body: some View {
        NativeGlassControlMaterial(
            shape: AnyShape(Circle()),
            interactive: true
        )
    }
}

struct NativeGlassControlMaterial: View {
    var shape: AnyShape = AnyShape(Capsule(style: .continuous))
    var interactive = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), !reduceTransparency {
            if interactive {
                Color.clear
                    .glassEffect(.regular.interactive(), in: shape)
            } else {
                Color.clear
                    .glassEffect(.regular, in: shape)
            }
        } else if reduceTransparency {
            shape
                .fill(UIConfig.fixedDark("glassReducedSurface", 0xFAFBF9, 0x1D231F))
        } else {
            fallback
        }
        #else
        fallback
        #endif
        }
        .overlay {
            shape.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(scheme == .dark ? 0.10 : 0.30),
                        Color.clear,
                        Color.black.opacity(scheme == .dark ? 0.10 : 0.025)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .allowsHitTesting(false)
        }
        .overlay {
            shape.stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(scheme == .dark ? 0.34 : 0.62),
                        Color.white.opacity(scheme == .dark ? 0.08 : 0.20),
                        Color.black.opacity(scheme == .dark ? 0.20 : 0.055)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.65
            )
        }
        .shadow(color: Color.black.opacity(scheme == .dark ? 0.28 : 0.09),
                radius: 8, x: 0, y: 4)
        .allowsHitTesting(false)
    }

    private var fallback: some View {
        shape
            .fill(.ultraThinMaterial)
    }
}

struct NativeGlassPlusButton: View {
    let action: () -> Void

    var body: some View {
        NativeGlassIconButton(symbol: "plus", label: Tr("更多"), action: action)
    }
}

struct NativeGlassIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16.5, weight: .semibold))
                .foregroundStyle(Color(hex: 0x34C759))
                .frame(width: 38, height: 38)
                .contentShape(Circle())
        }
        .buttonStyle(NavPlusPressStyle())
        .background { NativeGlassCircleBackground() }
        .accessibilityLabel(label)
    }
}

struct TopScrollProbe: View {
    var space: String
    var body: some View {
        GeometryReader { g in
            Color.clear.preference(key: TopScrollKey.self,
                                   value: -g.frame(in: .named(space)).minY)
        }
    }
}

extension View {
    func topScrollTracking(_ scrolled: Binding<CGFloat>, space: String) -> some View {
        self
            .coordinateSpace(name: space)
            .onPreferenceChange(TopScrollKey.self) { v in
                let s = max(0, v)
                let current = scrolled.wrappedValue
                if s < 1, current != 0 {
                    scrolled.wrappedValue = 0
                } else if abs(s - current) >= 8 || (current < 8 && s >= 8) {
                    scrolled.wrappedValue = s
                }
            }
    }
}
