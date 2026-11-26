import SwiftUI

extension WeChatMessageCard {
    init(width: CGFloat = 268,
         padding: CGFloat = 13,
         mine: Bool,
         showTail: Bool,
         @ViewBuilder content: () -> Content) {
        self.init(width: width, padding: padding, content: content)
    }
}
