import SwiftUI

struct DeferredChatView: View {
    @EnvironmentObject private var app: AppState

    @ObservedObject private var burnFX = BurnFX.shared
    let chat: Chat

    init(chat: Chat) {
        self.chat = chat
        // Resolve the destination palette before body evaluation so the
        // navigation background cannot inherit the previous chat's theme.
        ChatThemeStore.shared.activate(chat.id)
    }

    var body: some View {
        ZStack {
            ChatTheme.page.ignoresSafeArea()
            ChatDetailView(
                chat: chat,
                initialMessages: app.prefetched[chat.id] ?? []
            )

            if burnFX.firing {
                FlameSweepOverlay()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
    }
}
