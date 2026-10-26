import SwiftUI

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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let blur = UIConfig.num("chatsNavGlassAlpha", 1)

        let mask = UIConfig.num("chatsNavMaskAlpha", 0)

        let raw = min(1, max(0, scrolled / max(1, offset)))

        let t = always ? 1 : pow(raw, 0.8)
        if t > 0.01 {

            Group {
                if scheme == .dark {

                    HarmonyDarkMask(strength: 0.98)
                } else {
                    ZStack {
                        Rectangle().fill(.bar)
                            .opacity(max(0, min(1, blur)) * t)
                        (UIConfig.colorIfSet("chatsNavMaskColor") ?? fallback)
                            .opacity(max(0, min(1, mask)) * t)

                        if UIConfig.num("navRimLight", 1) > 0 {
                            RadialGradient(colors: [Color.white.opacity(0.30 * t), Color.clear],
                                           center: UnitPoint(x: 0.14, y: 0.18),
                                           startRadius: 1, endRadius: 170)
                            VStack { Spacer()
                                Rectangle()
                                    .fill(LinearGradient(colors: [Color.clear,
                                                                  Color.white.opacity(0.22 * t),
                                                                  Color.clear],
                                                         startPoint: .leading, endPoint: .trailing))
                                    .frame(height: 0.5)
                            }
                        }
                    }
                }
            }
            .ignoresSafeArea(edges: .top)

            .allowsHitTesting(false)
        }
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
        ZStack {
            GlassBackground(shape: Capsule(style: .continuous),
                            opacity: scheme == .dark ? 0.78 : 0.88,
                            edgeAlpha: scheme == .dark ? 0.26 : 0.42,
                            shadow: true,
                            seed: 0.57,
                            native: true)
            Capsule(style: .continuous)
                .fill(UIConfig.color("navPlusBg", 0x0F5A3C, 0x0F5A3C))
                .opacity(scheme == .dark ? 0.28 : 0.14)
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(scheme == .dark ? 0.22 : 0.58),
                        lineWidth: 0.7)
        }
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
                if s > scrolled.wrappedValue || s < 1 {
                    if abs(s - scrolled.wrappedValue) > 0.5 { scrolled.wrappedValue = s }
                }
            }
    }
}
