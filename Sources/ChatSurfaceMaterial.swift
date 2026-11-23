import SwiftUI
import UIKit

struct ChatSurfaceStyle {
    var fill: Color
    var fillEnd: Color
    var highlight: Color
    var shade: Color
    var border: Color
}

enum ChatSurfaceMaterial {
    static func bubble(mine: Bool,
                       dark: Bool,
                       glass: Bool) -> ChatSurfaceStyle {
        let base = mine ? ChatTheme.bubbleMine : ChatTheme.bubbleOther
        guard glass else {
            return ChatSurfaceStyle(
                fill: base,
                fillEnd: base,
                highlight: .clear,
                shade: .clear,
                border: .clear
            )
        }
        let fill = base.opacity(mine ? 0.84 : 0.74)
        return ChatSurfaceStyle(
            fill: fill,
            fillEnd: fill.opacity(0.72),
            highlight: Color.white.opacity(mine
                ? (dark ? 0.17 : 0.42)
                : (dark ? 0.12 : 0.72)),
            shade: Color.black.opacity(dark ? 0.07 : 0.035),
            border: Color.white.opacity(mine
                ? (dark ? 0.17 : 0.42)
                : (dark ? 0.12 : 0.72))
        )
    }

    static func system(dark: Bool, plain: Bool) -> ChatSurfaceStyle {
        if plain {
            return ChatSurfaceStyle(
                fill: .clear,
                fillEnd: .clear,
                highlight: .clear,
                shade: .clear,
                border: .clear
            )
        }
        return ChatSurfaceStyle(
            fill: dark ? Color.black.opacity(0.40) : Color.white.opacity(0.76),
            fillEnd: dark ? Color.black.opacity(0.34) : Color.white.opacity(0.68),
            highlight: dark ? Color.white.opacity(0.055) : Color.white.opacity(0.18),
            shade: dark ? Color.black.opacity(0.06) : Color.clear,
            border: dark ? Color.white.opacity(0.16) : Color.black.opacity(0.07)
        )
    }

    static func uiBubble(base: UIColor,
                         mine: Bool,
                         dark: Bool,
                         glass: Bool) -> (fill: UIColor,
                                          highlight: UIColor,
                                          shade: UIColor,
                                          border: UIColor) {
        guard glass else { return (base, .clear, .clear, .clear) }
        return (
            base.withAlphaComponent(mine ? 0.84 : 0.74),
            UIColor.white.withAlphaComponent(mine
                ? (dark ? 0.17 : 0.42)
                : (dark ? 0.12 : 0.72)),
            UIColor.black.withAlphaComponent(dark ? 0.07 : 0.035),
            UIColor.white.withAlphaComponent(mine
                ? (dark ? 0.17 : 0.42)
                : (dark ? 0.12 : 0.72))
        )
    }

    static func uiSystem(dark: Bool,
                         plain: Bool) -> (fill: UIColor,
                                          highlight: UIColor,
                                          shade: UIColor,
                                          border: UIColor) {
        if plain { return (.clear, .clear, .clear, .clear) }
        return (
            dark ? UIColor.black.withAlphaComponent(0.40)
                 : UIColor.white.withAlphaComponent(0.76),
            dark ? UIColor.white.withAlphaComponent(0.055)
                 : UIColor.white.withAlphaComponent(0.18),
            dark ? UIColor.black.withAlphaComponent(0.06) : .clear,
            dark ? UIColor.white.withAlphaComponent(0.16)
                 : UIColor.black.withAlphaComponent(0.07)
        )
    }
}
