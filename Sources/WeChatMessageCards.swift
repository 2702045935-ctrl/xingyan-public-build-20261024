import SwiftUI

enum ChatMessageSurface {
    static let cardRadius: CGFloat = WhatsAppChatLayout.cornerRadius
    static let innerRadius: CGFloat = WhatsAppChatLayout.innerRadius
    static let mediaRadius: CGFloat = WhatsAppChatLayout.cornerRadius
    static let gridRadius: CGFloat = WhatsAppChatLayout.mediaTileRadius

    static var cardFill: Color {
        Color.dyn(0xFFFFFF, 0x1C1C1E)
    }

    static func cardFill(mine _: Bool) -> Color {
        cardFill
    }

    static var cardBorder: Color {
        Color.dyn(0xE7E7E8, 0x343436)
    }
}

struct WeChatMessageCard<Content: View>: View {
    var width: CGFloat = 268
    var padding: CGFloat = 13
    var verticalPadding: CGFloat = WhatsAppChatLayout.bubblePadV
    var mine: Bool? = nil
    var showTail: Bool = false
    let content: Content

    init(width: CGFloat = 268,
         padding: CGFloat = 13,
         verticalPadding: CGFloat? = nil,
         mine: Bool? = nil,
         showTail: Bool = false,
         @ViewBuilder content: () -> Content) {
        self.width = width
        self.padding = padding
        self.verticalPadding = verticalPadding
            ?? (padding == 0 ? 0 : WhatsAppChatLayout.bubblePadV)
        self.mine = mine
        self.showTail = showTail
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if let mine {
            content
                .padding(.horizontal, padding)
                .padding(.vertical, verticalPadding)
                .frame(width: width, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: ChatMessageSurface.cardRadius,
                                     style: .continuous)
                        .fill(ChatMessageSurface.cardFill)
                }
                .clipShape(RoundedRectangle(cornerRadius: ChatMessageSurface.cardRadius,
                                            style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ChatMessageSurface.cardRadius,
                                     style: .continuous)
                        .stroke(ChatMessageSurface.cardBorder, lineWidth: 0.5)
                }
                .contentShape(RoundedRectangle(cornerRadius: ChatMessageSurface.cardRadius,
                                               style: .continuous))
        } else {
            content
                .padding(.horizontal, padding)
                .padding(.vertical, verticalPadding)
                .frame(width: width, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: ChatMessageSurface.cardRadius,
                                     style: .continuous)
                        .fill(ChatMessageSurface.cardFill)
                }
                .clipShape(RoundedRectangle(cornerRadius: ChatMessageSurface.cardRadius,
                                            style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ChatMessageSurface.cardRadius,
                                     style: .continuous)
                        .stroke(ChatMessageSurface.cardBorder, lineWidth: 0.5)
                }
                .contentShape(RoundedRectangle(cornerRadius: ChatMessageSurface.cardRadius,
                                               style: .continuous))
        }
    }
}

struct WeChatMessageCardFooter: View {
    let symbol: String
    let title: String
    var trailing: String = ""

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(C.green)
                .frame(width: 20, height: 20)
                .background(C.green.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: ChatMessageSurface.innerRadius,
                                                 style: .continuous))
            Text(title)
                .font(pfStyled(size: 11, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 5)
            if !trailing.isEmpty {
                Text(trailing)
                    .font(pfStyled(size: 10, weight: .medium))
                    .foregroundStyle(C.subLabel)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Color.primary.opacity(0.045),
                                in: Capsule(style: .continuous))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(C.subLabel)
    }
}
