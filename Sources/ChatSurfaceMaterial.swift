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
                       dark _: Bool,
                       glass _: Bool) -> ChatSurfaceStyle {
        let base = mine ? ChatTheme.bubbleMine : ChatTheme.bubbleOther
        return ChatSurfaceStyle(
            fill: base,
            fillEnd: base,
            highlight: .clear,
            shade: .clear,
            border: .clear
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
                         dark _: Bool,
                         glass _: Bool) -> (fill: UIColor,
                                          highlight: UIColor,
                                          shade: UIColor,
                                          border: UIColor) {
        (base, .clear, .clear, .clear)
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
