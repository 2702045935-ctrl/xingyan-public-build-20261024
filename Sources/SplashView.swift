import SwiftUI

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    @State private var progress: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                launchCanvas

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    VStack(spacing: 19) {
                        launchIcon(size: min(92, max(78, geo.size.width * 0.21)))

                        VStack(spacing: 6) {
                            Text("星言")
                                .font(.system(size: 30, weight: .semibold))
                                .tracking(1.2)
                                .foregroundStyle(.white)

                            Text("STAR CHAT")
                                .font(.system(size: 9.5, weight: .semibold))
                                .tracking(3.8)
                                .foregroundStyle(Color.white.opacity(0.34))
                        }
                    }
                    .scaleEffect(revealed ? 1 : 0.985)
                    .opacity(revealed ? 1 : 0)
                    .offset(y: -geo.size.height * 0.025)

                    Spacer(minLength: 0)

                    VStack(spacing: 13) {
                        Text("让每一句真心，都有回应")
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.32))

                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 112, height: 2)
                            .overlay(alignment: .leading) {
                                Capsule(style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                OrbitTheme.jadeDeep.opacity(0.72),
                                                OrbitTheme.jade
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: 112 * progress, height: 2)
                            }
                    }
                    .opacity(revealed ? 1 : 0)
                    .padding(.bottom, max(34, L.safeBottom + 22))
                }
                .padding(.horizontal, 28)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("星言"))
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.62)) {
                revealed = true
            }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.05).delay(0.08)) {
                progress = 1
            }
        }
    }

    private var launchCanvas: some View {
        ZStack {
            Color(hex: 0x040505)

            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x07110D), location: 0),
                    .init(color: Color(hex: 0x040505), location: 0.55),
                    .init(color: .black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                stops: [
                    .init(color: OrbitTheme.jadeDeep.opacity(0.12), location: 0),
                    .init(color: OrbitTheme.jadeDeep.opacity(0.025), location: 0.48),
                    .init(color: .clear, location: 1)
                ],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 0,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func launchIcon(size: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)

        Group {
            if let icon = AppIconImage.image {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                shape
                    .fill(
                        LinearGradient(
                            colors: [OrbitTheme.jade, OrbitTheme.jadeDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Text("星")
                            .font(.system(size: size * 0.40, weight: .bold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay {
            shape.stroke(Color.white.opacity(0.10), lineWidth: 0.7)
        }
        .shadow(color: Color.black.opacity(0.34), radius: 16, y: 8)
        .accessibilityHidden(true)
    }
}
