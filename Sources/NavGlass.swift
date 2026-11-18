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
                        NativeGlassHeaderMaterial()
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
struct NativeGlassHeaderMaterial: UIViewRepresentable {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    final class Coordinator {
        var token = ""
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: Self.visualEffect(dark: scheme == .dark))
        view.isUserInteractionEnabled = false
        view.contentView.backgroundColor = .clear
        applyReducedTransparency(to: view)
        context.coordinator.token = Self.effectToken(dark: scheme == .dark,
                                                     reduced: reduceTransparency)
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        let token = Self.effectToken(dark: scheme == .dark,
                                     reduced: reduceTransparency)
        guard context.coordinator.token != token else { return }
        context.coordinator.token = token
        view.effect = Self.visualEffect(dark: scheme == .dark)
        applyReducedTransparency(to: view)
    }

    private func applyReducedTransparency(to view: UIVisualEffectView) {
        if reduceTransparency {
            view.effect = nil
            view.backgroundColor = .secondarySystemBackground
        } else {
            view.effect = Self.visualEffect(dark: scheme == .dark)
            view.backgroundColor = .clear
        }
    }

    private static func visualEffect(dark: Bool) -> UIVisualEffect {
        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = false
            effect.tintColor = UIColor.white.withAlphaComponent(dark ? 0.025 : 0.055)
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

struct NativeTopGlassMask: View {
    var active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if !active {
                Color.clear
            } else if reduceTransparency {
                Color(uiColor: .systemBackground)
            } else {
                NativeGlassHeaderMaterial()
            }
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16),
                   value: active)
    }
}

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
                        .opacity(activeBaseOpacity ?? (scheme == .dark ? 0.72 : 0.56))
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
            .fill(UIConfig.fixedDark("glassReducedSurface", 0xFFFFFF, 0x1C1C1E))
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
    private let shape = Circle()

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), !reduceTransparency {
            Color.clear
                .glassEffect(.regular.interactive(), in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.20), lineWidth: 0.7))
                .shadow(color: Color.black.opacity(0.10), radius: 7, y: 3)
                .allowsHitTesting(false)
        } else if reduceTransparency {
            shape
                .fill(UIConfig.fixedDark("glassReducedSurface", 0xFFFFFF, 0x1C1C1E))
                .overlay {
                    shape.stroke(C.hairline.opacity(scheme == .dark ? 0.72 : 0.55),
                                 lineWidth: 0.7)
                }
                .shadow(color: Color.black.opacity(scheme == .dark ? 0.24 : 0.08),
                        radius: 6, y: 3)
                .allowsHitTesting(false)
        } else {
            fallback
        }
        #else
        fallback
        #endif
    }

    private var fallback: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.stroke(Color.white.opacity(0.32), lineWidth: 0.7))
            .shadow(color: Color.black.opacity(0.10), radius: 7, y: 3)
            .allowsHitTesting(false)
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
