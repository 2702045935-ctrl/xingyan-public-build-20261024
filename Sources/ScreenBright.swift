import SwiftUI
import UIKit

struct BrightenScreen: ViewModifier {

    @State private var saved: CGFloat?

    private let target: CGFloat = 1.0
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content
            .onAppear { brighten() }
            .onDisappear { restore() }

            .onChange(of: phase) { p in if p == .active { brighten() } }
    }

    private var screen: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let s = scenes.first?.screen { return s }
        return scenes.first?.windows.first?.screen
    }

    private func brighten() {
        guard let screen = screen else { return }
        let from = screen.brightness
        if saved == nil { saved = from }
        guard target > from else { return }

        let steps = 10
        for i in 1...steps {
            let d = Double(i) / Double(steps)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 * d) {

                let now = screen.brightness
                screen.brightness = max(now, from + (target - from) * CGFloat(d))
            }
        }
    }

    private func restore() {
        guard let screen = screen, let s = saved else { saved = nil; return }
        screen.brightness = s
        saved = nil
    }
}
