import SwiftUI
import UIKit

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

@MainActor
@discardableResult
func withSystemAnimation<Result>(_ animation: Animation? = .default,
                                 _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : animation, body)
}
