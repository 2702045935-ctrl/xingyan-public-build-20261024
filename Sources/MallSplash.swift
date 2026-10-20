import SwiftUI

struct MallSplashAdView: View {
    let splash: DDSplash

    var onClose: () -> Void

    var onTap: () -> Void

    @State private var left: Double = 3
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black

            GeometryReader { geo in
                let fit = UIConfig.num("splashFit", 1) > 0
                ZStack {
                    RemoteImage(path: splash.image ?? "", icon: "photo")
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .blur(radius: fit ? 26 : 0)
                    if fit {
                        Color.black.opacity(0.30)
                        RemoteImage(path: splash.image ?? "", icon: "photo", mode: .fit)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }

            Button { onClose() } label: {

                HStack(spacing: 6) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.30), lineWidth: 1.6)
                        Circle()
                            .trim(from: 0, to: max(0.001, min(1, left / max(1, splash.secs))))
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: left)
                        Text(String(Int(ceil(max(0, left)))))
                            .font(pf(10.5, .semibold)).monospacedDigit()
                            .foregroundColor(.white)
                    }
                    .frame(width: 18, height: 18)
                    Text(splash.skip).font(pf(13)).foregroundColor(.white)
                }
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(Capsule().fill(Color.black.opacity(0.38)))
                .overlay(Capsule().stroke(Color.white.opacity(0.28), lineWidth: 0.6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 14)
            .padding(.top, L.safeTop + 8)

            VStack {
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Text(Tr("广告"))
                        .font(pf(10.5))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 6).frame(height: 18)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.18)))
                    Text(Tr("点封面可以去看看"))
                        .font(pf(11)).foregroundColor(.white.opacity(0.6))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, L.safeBottom + 12)
            }
        }
        .ignoresSafeArea()
        .onAppear { left = splash.secs }
        .onReceive(ticker) { _ in
            left -= 1
            if left <= 0.01 { onClose() }
        }
    }
}
