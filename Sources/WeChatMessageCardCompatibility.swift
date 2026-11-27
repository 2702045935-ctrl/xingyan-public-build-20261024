import SwiftUI

enum ChatMessageSurface {
    static let cardRadius: CGFloat = 8
    static let innerRadius: CGFloat = 6
    static let mediaRadius: CGFloat = 8
    static let gridRadius: CGFloat = 5

    static var cardFill: Color {
        C.cardBg
    }

    static func cardFill(mine _: Bool) -> Color {
        cardFill
    }

    static var cardBorder: Color {
        Color.dyn(0xE7E7E8, 0x343436)
    }
}

extension WeChatMessageCard {
    init(width: CGFloat = 268,
         padding: CGFloat = 13,
         mine: Bool,
         showTail: Bool,
         @ViewBuilder content: () -> Content) {
        self.init(width: width, padding: padding, content: content)
    }
}
