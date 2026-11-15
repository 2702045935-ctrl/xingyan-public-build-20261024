import SwiftUI

private struct SystemAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    func systemAnimation<Value: Equatable>(_ animation: Animation,
                                           value: Value) -> some View {
        modifier(SystemAnimationModifier(animation: animation, value: value))
    }
}
