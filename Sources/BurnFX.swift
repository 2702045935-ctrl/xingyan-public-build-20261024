import SwiftUI

@MainActor
final class BurnFX: ObservableObject {
    static let shared = BurnFX()

    @Published var firing = false
    private var task: Task<Void, Never>?

    func fire() {
        firing = true
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if Task.isCancelled { return }
            await MainActor.run { self?.firing = false }
        }
    }
}

struct FlameSweepOverlay: View {

    private let dur: Double = 1.4
    @State private var t0 = Date()

    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { g, size in
                let t = ctx.date.timeIntervalSince(t0)
                guard t >= 0, t <= dur else { return }
                let p = t / dur
                let fade = 1 - p

                let edgeY = size.height * (1 - p)

                if edgeY > 0 {
                    let burnt = CGRect(x: 0, y: 0, width: size.width, height: edgeY)
                    g.fill(Path(burnt), with: .linearGradient(
                        Gradient(colors: [
                            Color.black.opacity(0.34 * fade),
                            Color(hex: 0x1A0E06).opacity(0.52 * fade),
                            Color(hex: 0x2A1206).opacity(0.30 * fade)
                        ]),
                        startPoint: CGPoint(x: 0, y: burnt.minY),
                        endPoint: CGPoint(x: 0, y: burnt.maxY)))
                }

                let flick = 1 + 0.18 * sin(t * 26)
                for i in 0..<64 {
                    let fi = Double(i)
                    let x = size.width * fi / 63
                    let wob = sin(fi * 0.9 + t * 7) * 5 + sin(fi * 2.3 + t * 3) * 2.5
                    let y = edgeY + wob
                    let r = (5.2 + 3.4 * (0.5 + 0.5 * sin(fi * 1.7 + t * 9))) * flick
                    let core = CGRect(x: x - r, y: y - r * 0.8, width: r * 2, height: r * 1.6)
                    g.fill(Path(ellipseIn: core), with: .radialGradient(
                        Gradient(colors: [Color(hex: 0xFFF3C4).opacity(0.95),
                                          Color(hex: 0xFFB024).opacity(0.75),
                                          Color(hex: 0xFF4D00).opacity(0.0)]),
                        center: CGPoint(x: core.midX, y: core.midY),
                        startRadius: 0, endRadius: r * 1.6))
                }

                if edgeY > 0 {
                    let hot = CGRect(x: 0, y: max(0, edgeY - 90), width: size.width, height: min(90, edgeY))
                    g.fill(Path(hot), with: .linearGradient(
                        Gradient(colors: [Color(hex: 0xFF6A00).opacity(0.0),
                                          Color(hex: 0xFF8A1E).opacity(0.34 * fade)]),
                        startPoint: CGPoint(x: 0, y: hot.minY),
                        endPoint: CGPoint(x: 0, y: hot.maxY)))
                }

                for i in 0..<26 {
                    let fi = Double(i)
                    let delay = fi * 0.028
                    let tt = max(0, t - delay) / dur
                    guard tt > 0, tt < 1 else { continue }
                    let baseX = size.width * ((fi * 0.618).truncatingRemainder(dividingBy: 1))
                    let rise = tt * (70 + 240 * ((fi * 0.37).truncatingRemainder(dividingBy: 1)))
                    let x = baseX + sin((tt + fi) * 6.28) * 16
                    let y = edgeY - rise
                    let r = (2.8 - 1.9 * tt) * (0.7 + 0.6 * ((fi * 0.73).truncatingRemainder(dividingBy: 1)))
                    let a = (1 - tt) * 0.95
                    g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                           with: .color(Color(hex: tt < 0.45 ? 0xFFE08A : 0xFF7A1E).opacity(a)))
                }

                for i in 0..<9 {
                    let fi = Double(i)
                    let delay = fi * 0.06
                    let tt = max(0, t - delay) / dur
                    guard tt > 0, tt < 1 else { continue }
                    let baseX = size.width * ((fi * 0.41 + 0.12).truncatingRemainder(dividingBy: 1))
                    let x = baseX + sin((tt + fi) * 3.14) * 26
                    let y = edgeY - 30 - tt * 200
                    let r = 26 + 60 * tt
                    let a = (1 - tt) * 0.16 * fade
                    g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                           with: .radialGradient(
                            Gradient(colors: [Color(hex: 0x9A9A9A).opacity(a),
                                              Color(hex: 0x6E6E6E).opacity(0.0)]),
                            center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
                }
            }
        }
        .onAppear { t0 = Date() }
        .allowsHitTesting(false)
    }
}
