import SwiftUI

struct PremiumGlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme

    private let radius: CGFloat
    private let tint: Color?
    private let content: Content

    init(radius: CGFloat = 28,
         tint: Color? = nil,
         @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .background {
                ZStack {
                    GlassBackground(shape: RoundedRectangle(cornerRadius: radius, style: .continuous),
                                    opacity: scheme == .dark ? 0.82 : 0.92,
                                    edgeAlpha: scheme == .dark ? 0.52 : 0.82,
                                    shadow: false,
                                    seed: 0.18,
                                    native: true,
                                    tint: tint)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color.white.opacity(scheme == .dark ? 0.025 : 0.10))
                    LinearGradient(colors: [Color.white.opacity(scheme == .dark ? 0.09 : 0.28),
                                            Color.clear],
                                   startPoint: .topLeading,
                                   endPoint: UnitPoint(x: 0.58, y: 0.45))
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.white.opacity(scheme == .dark ? 0.36 : 0.74),
                                                    Color.white.opacity(0.08),
                                                    C.green.opacity(scheme == .dark ? 0.18 : 0.12)],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing),
                            lineWidth: 0.8)
            }
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.34 : 0.12),
                    radius: 22, x: 0, y: 12)
    }
}

struct PremiumProfileBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            C.pageBg

            RadialGradient(colors: [Color(hex: 0x8FE1B4).opacity(scheme == .dark ? 0.10 : 0.17),
                                    Color.clear],
                           center: .topTrailing,
                           startRadius: 0,
                           endRadius: 320)

            RadialGradient(colors: [Color.white.opacity(scheme == .dark ? 0.035 : 0.52),
                                    Color.clear],
                           center: .topLeading,
                           startRadius: 0,
                           endRadius: 280)
        }
        .ignoresSafeArea()
    }
}
