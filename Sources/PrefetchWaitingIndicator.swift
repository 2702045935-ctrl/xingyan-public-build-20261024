import SwiftUI

struct PrefetchWaitingIndicator: View {
    let waiting: Bool
    let label: String

    @State private var visible = false
    @State private var revealTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(C.subLabel)
            Text(label)
                .font(pf(12.5))
                .foregroundStyle(C.subLabel)
        }
        .frame(maxWidth: .infinity)
        .frame(height: visible ? 46 : 1)
        .opacity(visible ? 1 : 0)
        .clipped()
        .animation(.easeOut(duration: 0.16), value: visible)
        .accessibilityElement(children: .combine)
        .accessibilityHidden(!visible)
        .onAppear {
            update(waiting)
        }
        .onChange(of: waiting) { next in
            update(next)
        }
        .onDisappear {
            revealTask?.cancel()
            revealTask = nil
            visible = false
        }
    }

    private func update(_ shouldWait: Bool) {
        revealTask?.cancel()
        revealTask = nil

        guard shouldWait else {
            visible = false
            return
        }

        revealTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            visible = true
        }
    }
}
