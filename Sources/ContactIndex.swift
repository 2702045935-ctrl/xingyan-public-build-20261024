import SwiftUI
import UIKit

func ctIdxWeight() -> Font.Weight { UIConfig.num("ctIdxBold", 1) > 0 ? .heavy : .regular }

struct ContactIndexBar: View {
    static let letters: [String] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ#".map { String($0) }

    var available: Set<String>
    var onPick: (String) -> Void
    var onSearch: () -> Void

    private let padV: CGFloat = 4.2

    private let searchBox: CGFloat = 22
    private let searchGap: CGFloat = 4

    @State private var active: String? = nil

    @GestureState private var touching = false

    private let haptic = UIImpactFeedbackGenerator(style: .heavy)

    private var fontSize: CGFloat { max(6, L.ctIdxSize) }
    private var rowH: CGFloat { max(fontSize, L.ctIdxItemH) }
    private var pitch: CGFloat { rowH }

    private var dotSide: CGFloat { max(15, rowH + 1.5) }

    private var initialLetter: String {
        Self.letters.first(where: { available.contains($0) }) ?? "A"
    }
    private var shownLetter: String { touching ? (active ?? initialLetter) : initialLetter }

    private var activeBg: Color { UIConfig.colorIfSet("ctIdxActiveBg") ?? C.green }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onSearch) {
                SVGIcon(markup: I.searchBig, size: 13, color: C.ctIdxColor)
                    .frame(width: searchBox, height: searchBox)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, searchGap)
            .accessibilityLabel(Tr("搜索"))

            VStack(spacing: 0) {
                ForEach(Self.letters, id: \.self) { L in
                    Text(L)
                        .font(pf(fontSize, ctIdxWeight()))

                        .foregroundColor(shownLetter == L ? .white : C.ctIdxColor)
                        .frame(height: rowH)
                        .frame(width: 22)
                        .background {
                            if shownLetter == L {
                                Circle()
                                    .fill(activeBg)
                                    .frame(width: dotSide, height: dotSide)
                            }
                        }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($touching) { _, state, _ in state = true }
                    .onChanged { value in
                        let i = max(0, min(Self.letters.count - 1,
                                           Int(floor(value.location.y / pitch))))
                        pick(Self.letters[i])
                    }
                    .onEnded { _ in
                        active = nil
                    }
            )
            .onDisappear { active = nil }
        }
        .padding(.vertical, padV)
        .frame(width: 22)
        .onAppear { haptic.prepare() }
        .onChange(of: available) { _ in haptic.prepare() }
    }

    private func pick(_ letter: String) {
        if active != letter {
            active = letter
            haptic.impactOccurred(intensity: 1.0)
            haptic.prepare()
        }
        onPick(letter)
    }
}

struct LetterBubble: View {
    let letter: String

    var body: some View {
        Text(letter)
            .font(pf(36, .semibold))
            .foregroundColor(.white)
            .frame(width: 78, height: 78)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.62))
            )
            .allowsHitTesting(false)
    }
}
