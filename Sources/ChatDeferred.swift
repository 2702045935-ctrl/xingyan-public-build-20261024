import SwiftUI
import UIKit

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

            ChatTransitionProbe {
                guard !ready else { return }
                withAnimation(.easeOut(duration: 0.16)) { ready = true }
            }
            .frame(width: 1, height: 1)
            .opacity(0.001)
            .allowsHitTesting(false)

            if burnFX.firing {
                FlameSweepOverlay()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
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

/// 导航 push 的 viewDidAppear 完成后再挂载重聊天页，不引入固定可见等待。
private struct ChatTransitionProbe: UIViewControllerRepresentable {
    let onReady: () -> Void

    func makeUIViewController(context: Context) -> ProbeController {
        ProbeController(onReady: onReady)
    }

    func updateUIViewController(_ controller: ProbeController, context: Context) {
        controller.onReady = onReady
    }

    final class ProbeController: UIViewController {
        var onReady: () -> Void
        private var fired = false

        init(onReady: @escaping () -> Void) {
            self.onReady = onReady
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func loadView() {
            view = UIView(frame: .zero)
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !fired else { return }
            fired = true
            DispatchQueue.main.async { [weak self] in self?.onReady() }
        }
    }
}
