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
    if let name = pfName(.regular), let font = UIFont(name: name, size: scaled) {
        return font
    }
    return .systemFont(ofSize: scaled)
}

struct FullScreenComposerView: View {
    @Binding var text: String
    let tint: Color
    let onSend: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Text(Tr("关闭"))
                        .font(pf(16, .medium))
                        .foregroundStyle(C.label)
                        .frame(minWidth: 52, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                VStack(spacing: 2) {
                    Text(Tr("全屏编辑"))
                        .font(pf(17, .semibold))
                        .foregroundStyle(C.label)
                    Text(Tr("草稿会自动保存"))
                        .font(pf(11.5))
                        .foregroundStyle(C.subLabel)
                }

                Spacer(minLength: 0)

                Button(action: onSend) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(C.green, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(trimmed.isEmpty)
                .opacity(trimmed.isEmpty ? 0.38 : 1)
                .accessibilityLabel(Tr("发送"))
            }
            .padding(.horizontal, 16)
            .frame(height: 58)

            Rectangle()
                .fill(C.hairline)
                .frame(height: 0.5)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(Tr("输入消息"))
                        .font(pf(18))
                        .foregroundStyle(C.subLabel.opacity(0.72))
                        .padding(.top, 18)
                        .padding(.leading, 21)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $text)
                    .font(pf(18))
                    .foregroundStyle(C.label)
                    .tint(tint)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .scrollDismissesKeyboard(.interactively)
                    .accessibilityLabel(Tr("消息内容"))
            }

            Rectangle()
                .fill(C.hairline)
                .frame(height: 0.5)

            HStack {
                Text("\(text.count) \(Tr("字"))")
                    .font(pf(12, .medium).monospacedDigit())
                Spacer(minLength: 0)
                Text(Tr("支持多行长文"))
                    .font(pf(12))
            }
            .foregroundStyle(C.subLabel)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .background(C.pageBg.ignoresSafeArea())
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
