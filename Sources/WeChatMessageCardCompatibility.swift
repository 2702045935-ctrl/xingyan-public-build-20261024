import SwiftUI

extension WeChatMessageCard {
    init(mine: Bool,
         showTail: Bool,
         @ViewBuilder content: () -> Content) {
        self.init(content: content)
    }
}
