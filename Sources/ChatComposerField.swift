import SwiftUI
import UIKit

final class ComposerTextView: UITextView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.height > 1, bounds.width > 1 {
            layoutManager.ensureLayout(for: textContainer)
            let used = ceil(layoutManager.usedRect(for: textContainer).height)
            let verticalInset = max(0, floor((bounds.height - used) / 2))
            if abs(textContainerInset.top - verticalInset) > 0.5 {
                textContainerInset = UIEdgeInsets(
                    top: verticalInset,
                    left: 0,
                    bottom: verticalInset,
                    right: 0
                )
            }
        }
        onLayout?()
    }
}

func chatComposerUIFont(_ size: CGFloat = 17) -> UIFont {
    let scaled = max(9, (size * fontScale * CareMode.scale).rounded())
    if !AppFontPrefs.family.isEmpty,
       let name = pfName(.regular),
       let font = UIFont(name: name, size: scaled) {
        return font
    }
    return .systemFont(ofSize: scaled)
}

struct FullScreenComposerView: View {
    @Binding var text: String
    let tint: Color
    let onSend: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var editorShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(C.label)
                    .frame(width: 42, height: 42)
                    .background {
                        GlassBackground(shape: Circle(),
                                        opacity: scheme == .dark ? 0.82 : 0.92,
                                        edgeAlpha: scheme == .dark ? 0.12 : 0.22,
                                        seed: 0.18)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("关闭"))

            VStack(alignment: .leading, spacing: 2) {
                Text(Tr("全屏编辑"))
                    .font(pf(18, .semibold))
                    .foregroundStyle(C.label)
                Text(Tr("草稿会自动保存"))
                    .font(pf(11.5))
                    .foregroundStyle(C.subLabel)
            }

            Spacer(minLength: 8)

            Button(action: onSend) {
                HStack(spacing: 7) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(Tr("发送"))
                        .font(pf(14, .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 15)
                .frame(height: 42)
                .background {
                    ZStack {
                        GlassBackground(shape: Capsule(),
                                        opacity: 0.96,
                                        edgeAlpha: 0.22,
                                        shadow: true,
                                        seed: 0.61,
                                        tint: tint.opacity(scheme == .dark ? 0.72 : 0.84))
                        Capsule().fill(tint.opacity(scheme == .dark ? 0.64 : 0.82))
                    }
                }
                .overlay {
                    Capsule().stroke(Color.white.opacity(0.20), lineWidth: 0.7)
                }
            }
            .buttonStyle(.plain)
            .disabled(trimmed.isEmpty)
            .opacity(trimmed.isEmpty ? 0.38 : 1)
            .accessibilityLabel(Tr("发送"))
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(Tr("输入消息"))
                    .font(pf(19))
                    .foregroundStyle(C.subLabel.opacity(0.72))
                    .padding(.top, 27)
                    .padding(.leading, 28)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .font(pf(19))
                .foregroundStyle(C.label)
                .lineSpacing(6)
                .tint(tint)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .scrollDismissesKeyboard(.interactively)
                .accessibilityLabel(Tr("消息内容"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            editorShape
                .fill(C.pageBg.opacity(scheme == .dark ? 0.20 : 0.10))
        }
        .background {
            GlassBackground(shape: editorShape,
                            opacity: scheme == .dark ? 0.90 : 0.96,
                            edgeAlpha: scheme == .dark ? 0.10 : 0.18,
                            shadow: true,
                            seed: 0.42)
        }
        .overlay {
            editorShape.stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(scheme == .dark ? 0.12 : 0.50),
                        Color.white.opacity(0.025),
                        C.hairline.opacity(scheme == .dark ? 0.42 : 0.28)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.8
            )
        }
        .clipShape(editorShape)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("\(text.count) \(Tr("字"))")
                .font(pf(12.5, .medium).monospacedDigit())
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(Tr("支持多行长文"))
            }
            .font(pf(12))
        }
        .foregroundStyle(C.subLabel)
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background {
            GlassBackground(shape: Capsule(),
                            opacity: scheme == .dark ? 0.78 : 0.90,
                            edgeAlpha: scheme == .dark ? 0.08 : 0.16,
                            seed: 0.73)
        }
        .overlay {
            Capsule().stroke(C.hairline.opacity(scheme == .dark ? 0.34 : 0.22),
                             lineWidth: 0.6)
        }
    }

    var body: some View {
        ZStack {
            C.pageBg.ignoresSafeArea()

            GlassBackground(shape: Rectangle(),
                            opacity: scheme == .dark ? 0.82 : 0.92,
                            edgeAlpha: 0.025,
                            seed: 0.91)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.white.opacity(scheme == .dark ? 0.018 : 0.08),
                    Color.clear,
                    Color.black.opacity(scheme == .dark ? 0.12 : 0.025)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 16) {
                header
                    .padding(.horizontal, 18)
                    .padding(.top, 10)

                editor
                    .padding(.horizontal, 16)

                footer
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
            }
        }
        .task {
            await Task.yield()
            focused = true
        }
    }
}

@MainActor
final class ChatComposerBridge: ObservableObject {
    fileprivate weak var textView: UITextView?
    fileprivate var onTextMutation: ((String) -> Void)?
    private var lastSelection = NSRange(location: 0, length: 0)

    fileprivate func attach(_ view: UITextView,
                            onTextMutation: ((String) -> Void)? = nil) {
        textView = view
        if let onTextMutation {
            self.onTextMutation = onTextMutation
        }
        rememberSelection(in: view)
    }

    fileprivate func rememberSelection(in view: UITextView) {
        lastSelection = view.selectedRange
    }

    func insert(_ text: String) {
        replaceSelection(with: text)
    }

    func deleteBackward() {
        guard let view = textView else { return }
        let current = view.text ?? ""
        let selected = currentSelection(in: view, textCount: (current as NSString).length)

        if selected.length > 0 {
            replaceSelection(with: "")
            return
        }

        guard selected.location > 0,
              let cursor = Range(NSRange(location: selected.location, length: 0), in: current),
              let from = current.index(cursor.lowerBound, offsetBy: -1, limitedBy: current.startIndex)
        else { return }

        let range = from..<cursor.lowerBound
        let cursorUTF16 = current.utf16.distance(from: current.startIndex, to: from)
        let next = current.replacingCharacters(in: range, with: "")
        apply(next, cursorUTF16: cursorUTF16, to: view)
    }

    private func replaceSelection(with text: String) {
        guard let view = textView else { return }
        let current = view.text ?? ""
        let selected = currentSelection(in: view, textCount: (current as NSString).length)
        guard let range = Range(selected, in: current) else { return }

        let insertion = text as NSString
        let next = current.replacingCharacters(in: range, with: text)
        let cursor = selected.location + insertion.length
        apply(next, cursorUTF16: cursor, to: view)
    }

    private func currentSelection(in view: UITextView, textCount: Int) -> NSRange {
        rememberSelection(in: view)
        let upper = max(0, textCount)
        let location = min(max(0, lastSelection.location), upper)
        let length = min(max(0, lastSelection.length), upper - location)
        return NSRange(location: location, length: length)
    }

    private func apply(_ text: String, cursorUTF16: Int, to view: UITextView) {
        view.text = text

        let upper = (text as NSString).length
        let safe = min(max(0, cursorUTF16), upper)
        let selection = NSRange(location: safe, length: 0)
        view.selectedRange = selection
        lastSelection = selection
        view.scrollRangeToVisible(selection)
        onTextMutation?(text)
    }
}

struct ChatComposerTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let bridge: ChatComposerBridge
    let font: UIFont
    let tintColor: UIColor
    let textColor: UIColor
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let onHeightChange: (CGFloat) -> Void
    let onBeginEditing: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ComposerTextView {
        let view = ComposerTextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.isScrollEnabled = true
        view.showsVerticalScrollIndicator = false
        view.alwaysBounceVertical = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.widthTracksTextView = true
        view.font = font
        view.tintColor = tintColor
        view.textColor = textColor
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bridge.attach(view) { value in
            context.coordinator.parent.text = value
        }
        view.onLayout = { [weak view, weak coordinator = context.coordinator] in
            guard let view, let coordinator else { return }
            coordinator.reportHeight(view)
        }
        return view
    }

    func updateUIView(_ view: ComposerTextView, context: Context) {
        context.coordinator.parent = self
        view.onLayout = { [weak view, weak coordinator = context.coordinator] in
            guard let view, let coordinator else { return }
            coordinator.reportHeight(view)
        }
        bridge.attach(view) { value in
            context.coordinator.parent.text = value
        }
        view.font = font
        view.tintColor = tintColor
        view.textColor = textColor

        if view.text != text {
            let selected = view.selectedRange
            view.text = text
            let length = (view.text as NSString).length
            let location = min(selected.location, length)
            let rangeLength = min(selected.length, length - location)
            view.selectedRange = NSRange(location: location, length: rangeLength)
            bridge.rememberSelection(in: view)
        }

        if focused && !view.isFirstResponder {
            DispatchQueue.main.async {
                guard self.focused, !view.isFirstResponder else { return }
                view.becomeFirstResponder()
            }
        } else if !focused && view.isFirstResponder {
            DispatchQueue.main.async {
                guard !self.focused, view.isFirstResponder else { return }
                view.resignFirstResponder()
            }
        }

        context.coordinator.reportHeight(view)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ChatComposerTextField
        private var lastHeight: CGFloat = 0

        init(parent: ChatComposerTextField) {
            self.parent = parent
        }

        @objc func textChanged(_ view: UITextView) {
            parent.text = view.text ?? ""
            parent.bridge.rememberSelection(in: view)
            reportHeight(view)
        }

        func textViewDidChange(_ textView: UITextView) {
            textChanged(textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.focused = true
            parent.bridge.rememberSelection(in: textView)
            parent.onBeginEditing()
            reportHeight(textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.focused = false
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.bridge.rememberSelection(in: textView)
        }

        func reportHeight(_ view: UITextView, force: Bool = false) {
            let width = max(1, view.bounds.width)
            guard width > 20 else { return }
            view.layoutManager.ensureLayout(for: view.textContainer)
            let fitting = ceil(view.layoutManager.usedRect(for: view.textContainer).height)
            let next = min(parent.maxHeight, max(parent.minHeight, ceil(fitting)))
            guard force || abs(next - lastHeight) > 0.5 else { return }
            lastHeight = next
            DispatchQueue.main.async {
                self.parent.onHeightChange(next)
            }
        }
    }
}
