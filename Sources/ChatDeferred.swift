import SwiftUI

struct DeferredChatView: View {
    @EnvironmentObject private var app: AppState

    @ObservedObject private var burnFX = BurnFX.shared
    let chat: Chat

    var body: some View {
        ZStack {
            defaultChatCanvasColor().ignoresSafeArea()
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
        .preferredColorScheme(app.preferredScheme)
        .background(defaultChatCanvasColor().ignoresSafeArea())
    }
}
