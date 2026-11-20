import Combine
import Foundation
import SwiftUI

@MainActor
final class MusicPresenceStore: ObservableObject {
    static let shared = MusicPresenceStore()

    @Published private(set) var byUser: [String: FriendNowPlaying] = [:]
    private var observer: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?
    private var loopTask: Task<Void, Never>?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .chrisMusicPresenceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        loopTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if !API.shared.token.isEmpty {
                    await self?.refresh()
                }
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        loopTask?.cancel()
    }

    func merge(_ list: [FriendNowPlaying]) {
        let now = Date().timeIntervalSince1970 * 1000
        let cutoff = now - 2 * 60 * 60 * 1000
        var next = byUser.filter { _, item in
            (item.at ?? 0) >= cutoff
        }
        for item in list where (item.at ?? 0) >= cutoff {
            next[item.id] = item
        }
        byUser = next
    }

    func refresh() async {
        if let running = refreshTask {
            await running.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            let list = await API.shared.friendsNowPlaying() ?? []
            self.merge(list)
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    func item(for userId: String) -> FriendNowPlaying? {
        byUser[userId]
    }
}

struct MusicListeningRing: View {
    var size: CGFloat
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotating = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(hex: 0x25D366),
                            Color(hex: 0x9BFFD1),
                            Color.clear,
                            Color(hex: 0x25D366)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(
                        lineWidth: max(1.4, size * 0.038),
                        lineCap: .round,
                        dash: [size * 0.20, size * 0.13]
                    )
                )
                .rotationEffect(.degrees(rotating ? 360 : 0))

            Image(systemName: "music.note")
                .font(.system(size: max(7, size * 0.19), weight: .bold))
                .foregroundStyle(.white)
                .frame(width: max(13, size * 0.31),
                       height: max(13, size * 0.31))
                .background(Circle().fill(Color(hex: 0x25D366)))
                .overlay(Circle().stroke(Color.white.opacity(0.75), lineWidth: 0.8))
                .offset(y: -size * 0.47)
                .rotationEffect(.degrees(rotating ? 360 : 0))
        }
        .frame(width: size, height: size)
        .opacity(active ? 1 : 0)
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            rotating = true
        }
        .onChange(of: active) { value in
            guard !reduceMotion else {
                rotating = false
                return
            }
            rotating = value
        }
        .animation(
            active && !reduceMotion
                ? .linear(duration: 3.2).repeatForever(autoreverses: false)
                : .easeOut(duration: 0.18),
            value: rotating
        )
    }
}
