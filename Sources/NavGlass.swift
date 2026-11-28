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
struct NativePremiumGlassMaterial: UIViewRepresentable {
    let dark: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = UIColor(hex: dark ? 0x1C1C1E : 0xF5F6F4)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        view.backgroundColor = UIColor(hex: dark ? 0x000000 : 0xF5F6F4)
    }
}

struct NativeGlassHeaderMaterial: UIViewRepresentable {
    var forcedDark: Bool? = nil

    @Environment(\.colorScheme) private var scheme

    func makeUIView(context: Context) -> UIView {
        let dark = forcedDark ?? (scheme == .dark)
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = UIColor(hex: dark ? 0x101412 : 0xF5F6F4)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        let dark = forcedDark ?? (scheme == .dark)
        view.backgroundColor = UIColor(hex: dark ? 0x101412 : 0xF5F6F4)
    }
}
#endif

#if canImport(UIKit)
/// 顶栏的可靠磨砂层。Liquid Glass 在部分自定义导航容器里几乎透明，
/// 这里直接使用系统材质模糊，保证内容进入标题区后确实被遮住。
struct NativeFrostedHeaderMaterial: UIViewRepresentable {
    @Environment(\.colorScheme) private var scheme

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: effect)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        view.effect = effect
    }

    private var effect: UIVisualEffect {
        UIBlurEffect(style: scheme == .dark
                     ? .systemMaterialDark
                     : .systemMaterialLight)
    }
}
#endif

#if canImport(UIKit)
struct NativeMediaGlassMaterial: UIViewRepresentable {
    var interactive = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: effect)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        view.effect = effect
    }

    private var effect: UIVisualEffect? {
        guard !reduceTransparency else { return nil }
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect(style: .regular)
            glass.isInteractive = interactive
            return glass
        }
        return UIBlurEffect(style: scheme == .dark
                            ? .systemThinMaterialDark
                            : .systemThinMaterialLight)
    }
}
#endif

struct NativeMediaGlassSurface: View {
    var shape: AnyShape = AnyShape(Capsule(style: .continuous))
    var interactive = false
    var showsEdge = true

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                shape.fill(C.controlSurface)
            } else {
                NativeMediaGlassMaterial(interactive: interactive)
                    .clipShape(shape)
            }
        }
        .overlay {
            if showsEdge {
                shape.stroke(Color.white.opacity(0.12), lineWidth: 0.6)
            }
        }
        .allowsHitTesting(false)
    }
}

struct NativeMediaGlassCircleBackground: View {
    var body: some View {
        NativeMediaGlassSurface(
            shape: AnyShape(Circle()),
            interactive: true
        )
    }
}

struct NativeTopGlassMask: View {
    var active: Bool
    var base: Color = C.pageBg

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if !active {
                Color.clear
            } else {
                ZStack {
                    if !reduceTransparency {
                        NativeFrostedHeaderMaterial()
                    }
                    base.opacity(reduceTransparency ? 1 : 0.90)
                }
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
                    LinearGradient(
                        stops: [
                            .init(color: base.opacity(
                                activeBaseOpacity ?? (scheme == .dark ? 0.50 : 0.34)
                            ),
                                  location: 0),
                            .init(color: base.opacity(scheme == .dark ? 0.24 : 0.14),
                                  location: 0.64),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom)

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
        fallback
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
            .fill(C.navBg)
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
            Circle()
                .stroke(C.hairline, lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(scheme == .dark ? 0.18 : 0.10),
                radius: 4, y: 2)
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

    var body: some View {
        NativeMediaGlassSurface(shape: shape, interactive: interactive)
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
