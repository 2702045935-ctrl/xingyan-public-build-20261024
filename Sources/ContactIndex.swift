import SwiftUI
import UIKit

func ctIdxWeight() -> Font.Weight { UIConfig.num("ctIdxBold", 1) > 0 ? .heavy : .regular }

private struct ContactIndexSearchPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.93 : 1))
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.09),
                       value: configuration.isPressed)
    }
}

struct ContactIndexBar: View {
    static let letters: [String] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ#".map { String($0) }

    var available: Set<String>
    var onPick: (String) -> Void
    var onSearch: () -> Void
    var onHighlight: (String?) -> Void = { _ in }

    private let padV: CGFloat = 4.2

    private let searchBox: CGFloat = 26
    private let searchGap: CGFloat = 6

    @State private var active: String? = nil
    @State private var clearTask: Task<Void, Never>?

    private let haptic = UISelectionFeedbackGenerator()

    private var fontSize: CGFloat { max(6.5, L.ctIdxSize - 0.5) }
    private var rowH: CGFloat { max(fontSize, L.ctIdxItemH) }
    private var pitch: CGFloat { rowH }

    private var dotSide: CGFloat { max(16, rowH + 2) }

    private var availableLetters: [String] {
        Self.letters.filter { available.contains($0) }
    }
    private var displayedLetters: [String] { Self.letters }
    private var shownLetter: String? { active }

    var body: some View {
        VStack(spacing: searchGap) {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                onSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(OrbitTheme.jade)
                    .frame(width: searchBox, height: searchBox)
                    .background(Circle().fill(OrbitTheme.raised))
                    .overlay(Circle().stroke(OrbitTheme.divider, lineWidth: 0.6))
                    .shadow(color: Color.black.opacity(0.08), radius: 5, y: 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ContactIndexSearchPressStyle())
            .accessibilityLabel(Tr("搜索"))

            VStack(spacing: 0) {
                ForEach(displayedLetters, id: \.self) { L in
                    Text(L)
                        .font(pfStyled(size: fontSize, weight: shownLetter == L ? .bold : .medium))

                        .foregroundColor(
                            shownLetter == L
                                ? .white
                                : (available.contains(L)
                                    ? OrbitTheme.tertiary
                                    : OrbitTheme.tertiary.opacity(0.28))
                        )
                        .frame(height: rowH)
                        .frame(width: 18)
                        .background {
                            if shownLetter == L {
                                Capsule(style: .continuous)
                                    .fill(OrbitTheme.jade)
                                    .frame(width: dotSide, height: dotSide)
                            }
                        }
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Tr("联系人索引"))
            .accessibilityValue(shownLetter ?? "")
            .accessibilityHint(Tr("上下轻扫切换字母"))
            .accessibilityAdjustableAction { direction in
                guard !availableLetters.isEmpty else { return }
                switch direction {
                case .increment:
                    let current = active.flatMap { availableLetters.firstIndex(of: $0) }
                    let next = current.map { min(availableLetters.count - 1, $0 + 1) } ?? 0
                    pick(availableLetters[next])
                case .decrement:
                    let current = active.flatMap { availableLetters.firstIndex(of: $0) }
                    let next = current.map { max(0, $0 - 1) } ?? (availableLetters.count - 1)
                    pick(availableLetters[next])
                @unknown default:
                    return
                }
                scheduleHighlightEnd()
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !displayedLetters.isEmpty else { return }
                        clearTask?.cancel()
                        let i = max(0, min(displayedLetters.count - 1,
                                           Int(floor(value.location.y / pitch))))
                        guard let letter = nearestAvailableLetter(to: i) else { return }
                        pick(letter)
                    }
                    .onEnded { _ in
                        scheduleHighlightEnd()
                    }
            )
            .onDisappear {
                clearTask?.cancel()
                active = nil
                onHighlight(nil)
            }
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(OrbitTheme.field.opacity(0.92))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(OrbitTheme.divider, lineWidth: 0.6)
                    )
            )
        }
        .padding(.vertical, padV)
        .frame(width: 28)
        .onAppear { haptic.prepare() }
        .onChange(of: available) { next in
            if let active, !next.contains(active) {
                self.active = nil
                onHighlight(nil)
            }
            haptic.prepare()
        }
    }

    private func pick(_ letter: String) {
        guard active != letter else { return }
        active = letter
        onHighlight(letter)
        onPick(letter)
        haptic.selectionChanged()
        haptic.prepare()
    }

    private func nearestAvailableLetter(to index: Int) -> String? {
        guard !availableLetters.isEmpty else { return nil }
        let clamped = max(0, min(displayedLetters.count - 1, index))
        if let forward = displayedLetters[clamped...].first(where: available.contains) {
            return forward
        }
        return displayedLetters[..<clamped].reversed().first(where: available.contains)
    }

    private func scheduleHighlightEnd() {
        clearTask?.cancel()
        clearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            active = nil
            onHighlight(nil)
        }
    }
}

struct LetterBubble: View {
    let letter: String

    var body: some View {
        Text(letter)
            .font(pfStyled(size: 34, weight: .bold))
            .foregroundColor(OrbitTheme.ink)
            .frame(width: 74, height: 74)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(OrbitTheme.raised.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(OrbitTheme.jade.opacity(0.42), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.16), radius: 16, y: 7)
            )
            .allowsHitTesting(false)
    }
}
