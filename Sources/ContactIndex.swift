import SwiftUI
import UIKit

func ctIdxWeight() -> Font.Weight {
    UIConfig.num("ctIdxBold", 1) > 0 ? .heavy : .regular
}

struct ContactIndexBar: View {
    static let letters: [String] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ#".map { String($0) }

    var available: Set<String>
    var onPick: (String) -> Void
    var onSearch: () -> Void
    var onHighlight: (String?) -> Void = { _ in }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let padV: CGFloat = 4.2

    private var accessibilityScale: CGFloat {
        switch dynamicTypeSize {
        case .accessibility1: return 1.08
        case .accessibility2: return 1.14
        case .accessibility3: return 1.20
        case .accessibility4: return 1.26
        case .accessibility5: return 1.32
        default: return 1
        }
    }

    private var fontSize: CGFloat {
        max(6.5, min(14, (L.ctIdxSize - 0.5) * accessibilityScale))
    }

    private var rowH: CGFloat {
        max(fontSize, min(24, L.ctIdxItemH * accessibilityScale))
    }

    private var dotSide: CGFloat {
        max(16, rowH + 2)
    }

    var body: some View {
        NativeContactIndexRepresentable(
            letters: Self.letters,
            available: available,
            fontSize: fontSize,
            rowHeight: rowH,
            dotSide: dotSide,
            accent: UIColor(ContactVisual.indexFill),
            indexInk: UIColor(Color.dyn(0x4A4A4F, 0xB8BCC2)),
            activeInk: UIColor.white.withAlphaComponent(0.98),
            onPick: onPick,
            onHighlight: onHighlight
        )
        .padding(.vertical, 5)
        .padding(.vertical, padV)
        .frame(width: 44)
    }
}

private struct NativeContactIndexRepresentable: UIViewRepresentable {
    let letters: [String]
    let available: Set<String>
    let fontSize: CGFloat
    let rowHeight: CGFloat
    let dotSide: CGFloat
    let accent: UIColor
    let indexInk: UIColor
    let activeInk: UIColor
    let onPick: (String) -> Void
    let onHighlight: (String?) -> Void

    func makeUIView(context: Context) -> NativeContactIndexControl {
        let view = NativeContactIndexControl()
        configure(view)
        return view
    }

    func updateUIView(_ view: NativeContactIndexControl, context: Context) {
        configure(view)
    }

    private func configure(_ view: NativeContactIndexControl) {
        view.onPick = onPick
        view.onHighlight = onHighlight
        view.update(
            letters: letters,
            available: available,
            fontSize: fontSize,
            rowHeight: rowHeight,
            dotSide: dotSide,
            accent: accent,
            indexInk: indexInk,
            activeInk: activeInk,
            accessibilityLabel: Tr("联系人索引"),
            accessibilityHint: Tr("上下轻扫切换字母")
        )
    }
}

private final class NativeContactIndexControl: UIControl {
    var onPick: (String) -> Void = { _ in }
    var onHighlight: (String?) -> Void = { _ in }

    private let activeBubble = UIView()
    private let labels = (0..<27).map { _ in UILabel() }
    private let haptic = UISelectionFeedbackGenerator()
    private var letters: [String] = []
    private var available: Set<String> = []
    private var activeLetter: String?
    private var fontSize: CGFloat = 12
    private var preferredRowHeight: CGFloat = 18
    private var dotSide: CGFloat = 18
    private var accent: UIColor = .systemTeal
    private var indexInk: UIColor = .secondaryLabel
    private var activeInk: UIColor = .white
    private var clearWorkItem: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        isAccessibilityElement = true
        accessibilityTraits = .adjustable

        activeBubble.isUserInteractionEnabled = false
        activeBubble.isHidden = true
        activeBubble.layer.cornerCurve = .continuous
        addSubview(activeBubble)

        for label in labels {
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.82
            label.isUserInteractionEnabled = false
            label.isAccessibilityElement = false
            addSubview(label)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        clearWorkItem?.cancel()
    }

    func update(letters: [String],
                available: Set<String>,
                fontSize: CGFloat,
                rowHeight: CGFloat,
                dotSide: CGFloat,
                accent: UIColor,
                indexInk: UIColor,
                activeInk: UIColor,
                accessibilityLabel: String,
                accessibilityHint: String) {
        let visibleChanged = self.letters != letters
            || self.available != available
            || self.fontSize != fontSize
            || self.preferredRowHeight != rowHeight
            || self.dotSide != dotSide
            || self.accent != accent
            || self.indexInk != indexInk
            || self.activeInk != activeInk

        self.letters = letters
        self.available = available
        self.fontSize = fontSize
        self.preferredRowHeight = rowHeight
        self.dotSide = dotSide
        self.accent = accent
        self.indexInk = indexInk
        self.activeInk = activeInk
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint

        if let activeLetter, !available.contains(activeLetter) {
            DispatchQueue.main.async { [weak self] in
                self?.setActiveLetter(nil, notify: true)
            }
        }
        if visibleChanged {
            applyLabelStyle()
            setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !letters.isEmpty else { return }

        let rowHeight = currentRowHeight
        let totalHeight = rowHeight * CGFloat(letters.count)
        let top = (bounds.height - totalHeight) / 2
        let width = min(bounds.width, max(18, dotSide - 3))
        let bubbleHeight = min(rowHeight, max(8, dotSide - 3))
        let x = (bounds.width - width) / 2

        for (index, label) in labels.enumerated() where index < letters.count {
            label.frame = CGRect(
                x: x,
                y: top + CGFloat(index) * rowHeight,
                width: width,
                height: rowHeight
            )
        }

        if let activeIndex = activeLetter.flatMap(letters.firstIndex(of:)) {
            activeBubble.frame = CGRect(
                x: x,
                y: top + CGFloat(activeIndex) * rowHeight + (rowHeight - bubbleHeight) / 2,
                width: width,
                height: bubbleHeight
            )
            activeBubble.layer.cornerRadius = bubbleHeight / 2
        }
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        clearWorkItem?.cancel()
        haptic.prepare()
        updatePick(at: touch.location(in: self))
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updatePick(at: touch.location(in: self))
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        scheduleHighlightEnd()
    }

    override func cancelTracking(with event: UIEvent?) {
        scheduleHighlightEnd()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            haptic.prepare()
        }
    }

    override func accessibilityIncrement() {
        stepAccessibility(by: 1)
    }

    override func accessibilityDecrement() {
        stepAccessibility(by: -1)
    }

    private var currentRowHeight: CGFloat {
        guard !letters.isEmpty, bounds.height > 0 else {
            return preferredRowHeight
        }
        return min(preferredRowHeight, bounds.height / CGFloat(letters.count))
    }

    private func updatePick(at point: CGPoint) {
        guard !letters.isEmpty else { return }
        let rowHeight = max(1, currentRowHeight)
        let totalHeight = rowHeight * CGFloat(letters.count)
        let top = (bounds.height - totalHeight) / 2
        let index = max(0, min(letters.count - 1,
                               Int(floor((point.y - top) / rowHeight))))
        guard let letter = nearestAvailableLetter(to: index) else { return }
        setActiveLetter(letter, notify: true)
        haptic.selectionChanged()
        haptic.prepare()
    }

    private func setActiveLetter(_ letter: String?, notify: Bool) {
        guard activeLetter != letter else { return }
        activeLetter = letter
        applyLabelStyle()
        setNeedsLayout()
        accessibilityValue = letter
        if notify {
            onHighlight(letter)
            if let letter {
                onPick(letter)
            }
        }
    }

    private func applyLabelStyle() {
        let activeWeight = UIConfig.num("ctIdxBold", 1) > 0 ? UIFont.Weight.bold : .medium
        for (index, letter) in letters.enumerated() where index < labels.count {
            let label = labels[index]
            let isActive = letter == activeLetter
            let isAvailable = available.contains(letter)
            label.isHidden = false
            label.text = letter
            label.font = .systemFont(ofSize: fontSize,
                                     weight: isActive ? activeWeight : .medium)
            label.textColor = isActive
                ? activeInk
                : indexInk.withAlphaComponent(isAvailable ? 1 : 0.22)
        }

        if letters.count < labels.count {
            for label in labels[letters.count...] {
                label.isHidden = true
            }
        }

        activeBubble.isHidden = activeLetter == nil
        activeBubble.backgroundColor = accent
        activeBubble.layer.cornerCurve = .continuous
    }

    private func stepAccessibility(by delta: Int) {
        let availableLetters = letters.filter(available.contains)
        guard !availableLetters.isEmpty else { return }
        let current = activeLetter.flatMap(availableLetters.firstIndex(of:))
        let base = current ?? (delta > 0 ? -1 : availableLetters.count)
        let next = max(0, min(availableLetters.count - 1, base + delta))
        setActiveLetter(availableLetters[next], notify: true)
        haptic.selectionChanged()
        scheduleHighlightEnd()
    }

    private func nearestAvailableLetter(to index: Int) -> String? {
        guard !available.isEmpty, !letters.isEmpty else { return nil }
        let clamped = max(0, min(letters.count - 1, index))
        if let forward = letters[clamped...].first(where: available.contains) {
            return forward
        }
        return letters[..<clamped].reversed().first(where: available.contains)
    }

    private func scheduleHighlightEnd() {
        clearWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.isTracking else { return }
            self.setActiveLetter(nil, notify: true)
        }
        clearWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: item)
    }
}

struct LetterBubble: View {
    let letter: String

    var body: some View {
        Text(letter)
            .font(pfStyled(size: 34, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 66, height: 66)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.dyn(0x62666B, 0x4A4D52).opacity(0.88))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.6)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 5, y: 2)
            )
            .allowsHitTesting(false)
    }
}
