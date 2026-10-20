import SwiftUI

struct DeferredChatView: View {
    @EnvironmentObject private var app: AppState

    @ObservedObject private var burnFX = BurnFX.shared
    let chat: Chat
    @State private var ready = false

    var body: some View {
        ZStack {
            C.pageBg.ignoresSafeArea()
            if ready {
                ChatDetailView(chat: chat)
                    .transition(.opacity)
            } else {

                chatBackdrop
                    .ignoresSafeArea()
            }

            if burnFX.firing {
                FlameSweepOverlay()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .task {
            guard !ready else { return }

            try? await Task.sleep(nanoseconds: 350_000_000)
            withAnimation(.easeOut(duration: 0.16)) { ready = true }
        }
    }

    @ViewBuilder private var chatBackdrop: some View {
        ZStack {
            C.pageBg
            if !bgPath.isEmpty {
                RemoteImage(path: bgPath)
                    .id(bgPath)
            }
        }
    }

    private var bgPath: String {
        let synced = app.me?.chatBackgrounds?[chat.id] ?? ""
        let per = synced.isEmpty ? ChatBgStore.shared.get(chat.id) : synced
        if !per.isEmpty { return per == "auto" ? "" : per }
        let v = app.me?.chatBackground ?? "auto"
        if v.isEmpty || v == "auto" {
            let def = app.defaultChatBackground
            return def == "auto" ? "" : def
        }
        return v
    }
}
